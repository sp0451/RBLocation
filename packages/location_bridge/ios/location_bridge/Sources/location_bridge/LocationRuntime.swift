import Foundation
import Flutter
import CoreLocation
import UIKit
import UserNotifications

/// Native state is authoritative. MainActor serializes snapshots, FFI has its own serial queue.
@MainActor
final class LocationRuntime: NSObject, NativeLocationApi, @preconcurrency CLLocationManagerDelegate {
    private let runtimeId = UUID().uuidString
    private var generation: Int64 = 0
    private var sequence: Int64 = 0
    private var connection: WireConnection = .disconnected
    private var sessionId: String?
    private var operation: WireOperation?
    private var sample: WireSample?
    // A new process cannot know whether a previous developer session still affects location.
    private var recoveryRequired = true
    private var failure: WireFailure?
    private var attached = false
    private var busy = false
    private var stopping = false
    private var clearSentAt: Date?
    private let manager = CLLocationManager()
    private let engine = IdeviceEngine()
    private let engineQueue = DispatchQueue(label: "com.clocation.location-bridge.engine", qos: .userInitiated)
    private let pairing = PairingCoordinator()
    private let events: NativeLocationEvents
    private var eventTail: Task<Void, Never>?

    init(messenger: FlutterBinaryMessenger) {
        events = NativeLocationEvents(binaryMessenger: messenger)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        pairing.onInteraction = { [weak self] interaction, attempt in
            guard let self, self.attached else { return }
            // Ephemeral pairing codes bypass snapshot/event replay and are never retained here.
            Task {
                guard self.attached, self.pairing.acceptsInteraction(attempt),
                    self.operation?.id == interaction.operationId, self.operation?.state == .pending else { return }
                try? await self.events.onPairingInteraction(interaction: interaction)
            }
        }
        pairing.onFinished = { [weak self] operationId, result in
            guard let self, self.operation?.id == operationId, self.operation?.kind == .pairing else { return }
            self.busy = false
            switch result {
            case .success:
                self.operation?.state = .acknowledged
                self.failure = nil
            case .failure(let error):
                self.failure = self.wireFailure(error, operationId: self.operation?.id)
                self.operation?.state = error.code == "cancelled" ? .cancelled : .failed
                self.operation?.failure = self.failure
            }
            self.operation?.occurredAtMillis = Self.now
            self.publish()
        }
    }

    private static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private var available: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        #endif
    }

    func getCapabilities() async throws -> WireCapabilities { capabilities() }
    private func capabilities() -> WireCapabilities {
        let record: Data?
        do { record = try PairingVault.load() } catch { record = nil }
        let authorization = manager.authorizationStatus
        let permitted = authorization == .authorizedAlways || authorization == .authorizedWhenInUse
        return WireCapabilities(platform: .ios, osVersion: UIDevice.current.systemVersion,
            engineAvailable: available, supportsPairing: available, isPaired: record != nil,
            prerequisites: [
                WirePrerequisite(id: "runtime", title: "原生定位引擎", detail: available ? "已链接固定版本 idevice；真机协议能力仍需实测" : "需要 iOS 27+ arm64 真机；模拟器不提供设备定位模拟",
                    state: available ? .satisfied : .missing, requiredForConnect: true),
                WirePrerequisite(id: "pairing", title: "本机配对", detail: record != nil ? "已保存本机受保护的配对记录；连接时验证设备密钥" : "请完成系统六位码配对",
                    state: record != nil ? .satisfied : .missing, requiredForConnect: true),
                WirePrerequisite(id: "developerMode", title: "开发者模式与设备准备", detail: "需手动启用开发者模式；Xcode 设备准备与 DDI 是否可用由实际握手检查",
                    state: connection == .ready ? .satisfied : .unknown, requiredForConnect: true, action: .developerSettings),
                WirePrerequisite(id: "externalTunnel", title: "LocalDevVPN", detail: connection == .ready ? "已通过外部隧道完成设备服务握手" : "请在 Wi-Fi 下连接 LocalDevVPN（10.7.0.1）；VPN 图标不能证明服务可用",
                    state: connection == .ready ? .satisfied : .unknown, requiredForConnect: true, action: .externalTunnel),
                WirePrerequisite(id: "observation", title: "本 App 定位观测", detail: "观测只证明本 App 收到的样本；第三方 App 需独立验收",
                    state: permitted ? .satisfied : .missing, requiredForConnect: false, action: .locationPermission)
            ])
    }

    func attach() async throws -> WireSnapshot {
        attached = true
        startObservationIfAllowed()
        return snapshot()
    }
    func getSnapshot() async throws -> WireSnapshot { snapshot() }
    func detach() async throws { attached = false }

    private func snapshot() -> WireSnapshot {
        WireSnapshot(runtimeId: runtimeId, generation: generation, sequence: sequence,
            connection: connection, recoveryRequired: recoveryRequired, capabilities: capabilities(),
            sessionId: sessionId, operation: operation, sample: sample, failure: failure)
    }

    private func publish() {
        sequence += 1
        guard attached else { return }
        let value = snapshot()
        let previous = eventTail
        eventTail = Task { [events] in
            await previous?.value
            try? await events.onSnapshot(snapshot: value)
        }
    }

    private func wireFailure(_ error: Error, operationId: String?) -> WireFailure {
        let value = error as? NativeFailure ?? NativeFailure("nativeFailure", "原生操作失败", "native")
        return WireFailure(code: value.code, message: value.message, stage: value.stage,
            retryable: value.code != "invalidCoordinate" && value.code != "unsupported", operationId: operationId)
    }

    private func reject(_ id: String, _ kind: WireOperationKind, _ error: NativeFailure) -> WireSnapshot {
        // Rejections are response-only: they must not replace an in-flight native operation.
        var value = snapshot()
        let reason = wireFailure(error, operationId: id)
        value.failure = reason
        value.operation = WireOperation(id: id, kind: kind, state: .failed,
            occurredAtMillis: Self.now, failure: reason)
        return value
    }

    private func begin(_ id: String, _ kind: WireOperationKind, coordinate: WireCoordinate? = nil) {
        busy = true
        failure = nil
        operation = WireOperation(id: id, kind: kind, state: .pending,
            occurredAtMillis: Self.now, coordinate: coordinate)
        publish()
    }

    private func execute(_ block: @escaping @Sendable (IdeviceEngine) throws -> Void) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            engineQueue.async { [engine] in
                continuation.resume(returning: Result { try block(engine) })
            }
        }
    }

    func connect(operationId: String) async throws -> WireSnapshot {
        guard available else { return reject(operationId, .connect, NativeFailure("unsupported", "需要 iOS 27+ 真机", "connect")) }
        guard !busy, !stopping else { return reject(operationId, .connect, NativeFailure("operationInProgress", "请等待当前操作结束", "connect")) }
        begin(operationId, .connect)
        connection = .connecting; publish()
        let token = generation
        let result = await execute { try $0.connect() }
        guard token == generation else { return snapshot() }
        busy = false
        switch result {
        case .success:
            sessionId = UUID().uuidString; connection = .ready
            operation?.state = .acknowledged
            startObservationIfAllowed()
        case .failure(let error):
            connection = .lost; failure = wireFailure(error, operationId: operationId)
            operation?.state = .failed; operation?.failure = failure
        }
        operation?.occurredAtMillis = Self.now; publish()
        return snapshot()
    }

    func setLocation(request: WireLocationRequest) async throws -> WireSnapshot {
        let point = request.coordinate
        guard point.latitude.isFinite, point.longitude.isFinite, (-90...90).contains(point.latitude),
              (-180...180).contains(point.longitude), request.accuracy.isFinite, request.accuracy > 0 else {
            return reject(request.operationId, .setLocation, NativeFailure("invalidCoordinate", "请输入有效 WGS84 经纬度和精度", "set"))
        }
        guard !busy, !stopping else { return reject(request.operationId, .setLocation, NativeFailure("operationInProgress", "清除或其他操作进行中，请完成后重新提交", "set")) }
        guard connection == .ready, available else { return reject(request.operationId, .setLocation, NativeFailure("notConnected", "请先连接设备服务", "set")) }
        begin(request.operationId, .setLocation, coordinate: point)
        recoveryRequired = true; clearSentAt = nil
        let token = generation
        let result = await execute { try $0.set(latitude: point.latitude, longitude: point.longitude) }
        guard token == generation else { return snapshot() }
        busy = false
        switch result {
        case .success: operation?.state = .sent
        case .failure(let error):
            connection = .lost; failure = wireFailure(error, operationId: request.operationId)
            operation?.state = .indeterminate; operation?.failure = failure
        }
        operation?.occurredAtMillis = Self.now; publish()
        return snapshot()
    }

    func clearLocation(operationId: String) async throws -> WireSnapshot {
        await stop(operationId: operationId, closing: false)
    }
    func closeSession(operationId: String) async throws -> WireSnapshot {
        await stop(operationId: operationId, closing: true)
    }

    private func stop(operationId: String, closing: Bool) async -> WireSnapshot {
        let kind: WireOperationKind = closing ? .closeSession : .clearLocation
        guard available else { return reject(operationId, kind, NativeFailure("unsupported", "需要 iOS 27+ 真机", "clear")) }
        guard !stopping else { return reject(operationId, kind, NativeFailure("operationInProgress", "正在清除定位", "clear")) }
        stopping = true
        generation += 1 // Invalidates late set/connect completions before clear enters the FFI queue.
        if pairing.active { await pairing.cancel() }
        begin(operationId, kind)
        recoveryRequired = true
        clearSentAt = nil
        if closing { connection = .closing; publish() }
        let result = await execute { try $0.clear() }
        switch result {
        case .success:
            operation?.state = .sent
            clearSentAt = Date()
            if !closing { connection = .ready; if sessionId == nil { sessionId = UUID().uuidString } }
            startObservationIfAllowed()
        case .failure(let error):
            failure = wireFailure(error, operationId: operationId)
            operation?.state = .indeterminate; operation?.failure = failure
            connection = .lost
        }
        operation?.occurredAtMillis = Self.now; publish()
        if closing {
            // Let fresh observations establish this App's restoration, bounded to 15 seconds.
            let deadline = Date().addingTimeInterval(15)
            while recoveryRequired, clearSentAt != nil, Date() < deadline {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            _ = await execute { $0.disconnect() }
            manager.stopUpdatingLocation()
            connection = .disconnected; sessionId = nil; generation += 1
        }
        busy = false; stopping = false; publish()
        return snapshot()
    }

    func startPairing(operationId: String) async throws -> WireSnapshot {
        guard available else { return reject(operationId, .pairing, NativeFailure("unsupported", "本机配对需要 iOS 27+ 真机", "pairing")) }
        guard !busy, !stopping, connection != .ready else {
            return reject(operationId, .pairing, NativeFailure("operationInProgress", "请先关闭当前会话再配对", "pairing"))
        }
        begin(operationId, .pairing)
        pairing.start(operationId: operationId)
        return snapshot()
    }

    func respondToPairing(response: WirePairingResponse) async throws {
        guard pairing.acceptsInteractionId(response.interactionId) else {
            throw PigeonError(code: "staleInteraction", message: "配对交互已结束或不属于当前配对，请重新开始", details: nil)
        }
        if response.cancelled { await pairing.cancel() }
        else if response.code != nil {
            throw PigeonError(code: "unsupportedInteraction", message: "本机配对请将 App 显示的验证码输入系统设置", details: nil)
        }
    }
    func cancelPairing() async throws { await pairing.cancel() }

    func openSetup(target: WireSetupTarget) async throws {
        switch target {
        case .locationPermission:
            manager.requestWhenInUseAuthorization()
        case .notificationPermission:
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .appSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            await UIApplication.shared.open(url)
        case .developerSettings, .locationSettings, .externalTunnel:
            throw PigeonError(code: "manualSetupRequired", message: "请按引导手动打开系统设置或 LocalDevVPN；iOS 没有可用的公开直达入口", details: nil)
        }
    }

    private func startObservationIfAllowed() {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse { manager.startUpdatingLocation() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startObservationIfAllowed(); publish()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last, value.horizontalAccuracy >= 0, CLLocationCoordinate2DIsValid(value.coordinate) else { return }
        let simulated = value.sourceInformation?.isSimulatedBySoftware
        sample = WireSample(coordinate: WireCoordinate(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude),
            accuracy: value.horizontalAccuracy, timestampMillis: Int64(value.timestamp.timeIntervalSince1970 * 1000), isSimulated: simulated)
        if let clearSentAt, value.timestamp >= clearSentAt, simulated == false,
           Date().timeIntervalSince(value.timestamp) < 15 {
            recoveryRequired = false
        }
        publish()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Observation errors never change DVT command evidence or infer restoration.
        if (error as? CLError)?.code == .denied { sample = nil; publish() }
    }
}
