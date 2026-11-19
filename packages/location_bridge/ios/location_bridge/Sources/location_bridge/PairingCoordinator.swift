import Foundation
import UIKit
import UserNotifications
import IdeviceRuntime

/// The callback owner is retained until the bounded Rust accept call has returned.
/// C strings are copied in their callback, before dispatching to the main actor.
@MainActor
final class PairingCoordinator {
    private let advertiser = PairableHostAdvertiser()
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelled = false
    private var expiresAtMillis: Int64 = 0
    private var interactionGate = PairingAttemptGate()
    private var workerAttempt: PairingAttempt?
    private var interactionIds: Set<String> = []
    private(set) var active = false
    var onInteraction: ((WirePairingInteraction, PairingAttempt) -> Void)?
    var onFinished: ((String, Result<Void, NativeFailure>) -> Void)?

    func start(operationId: String) {
        guard !active else { return }
        active = true; cancelled = false
        let attempt = interactionGate.begin(operationId: operationId)
        workerAttempt = attempt
        interactionIds.removeAll()
        expiresAtMillis = Int64(Date().addingTimeInterval(180).timeIntervalSince1970 * 1000)
        aurora_pairable_host_set_cancelled(false)
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "CLocation pairing") { [weak self] in
            Task { @MainActor in
                guard let self, self.acceptsInteraction(attempt) else { return }
                self.requestCancel()
            }
        }
        // A short system background grant may expire before pairing completes.
        // Expiration cancels the real listener; no hidden keep-alive is used.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let box = PairingCallbackBox(owner: self, attempt: attempt)
        DispatchQueue.global(qos: .userInitiated).async {
            let context = Unmanaged.passRetained(box).toOpaque()
            var record: OpaquePointer?
            let error = aurora_pairable_host_accept("CLocation", "Mac17,7",
                clocationPIN, context, clocationListening, context, clocationConnected, context, &record)
            let result: Result<Data, NativeFailure>
            do {
                try NativeFailure.check(error, stage: "pairing.accept")
                guard let record else { throw NativeFailure("pairingFailed", "系统未返回配对记录", "pairing.accept") }
                result = .success(try PairingVault.serialize(record))
            } catch { result = .failure(error as? NativeFailure ?? NativeFailure("pairingFailed", "配对失败", "pairing.accept")) }
            if let record { rp_pairing_file_free(record) }
            Unmanaged<PairingCallbackBox>.fromOpaque(context).release()
            Task { @MainActor in box.owner?.finish(result, attempt: box.attempt) }
        }
    }

    func requestCancel() {
        guard active else { return }
        cancelled = true
        interactionGate.invalidate()
        interactionIds.removeAll()
        aurora_pairable_host_set_cancelled(true)
        teardown()
    }

    func cancel() async {
        guard active else { return }
        requestCancel()
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    func acceptsInteraction(_ attempt: PairingAttempt) -> Bool {
        active && !cancelled && interactionGate.accepts(attempt)
    }

    func acceptsInteractionId(_ id: String) -> Bool {
        active && !cancelled && interactionIds.contains(id)
    }

    fileprivate func listening(port: UInt16, values: [String], attempt: PairingAttempt) {
        guard acceptsInteraction(attempt) else { return }
        advertiser.publish(port: port, identifier: values[0], name: values[1], model: values[2],
            authTag: values[3], version: values[4], minimumVersion: values[5]) { [weak self] in
                Task { @MainActor in
                    guard let self, self.acceptsInteraction(attempt) else { return }
                    self.requestCancel()
                }
            }
        interaction(kind: .confirmOnDevice, title: "在 设置 → 隐私与安全性 → 开发者模式 → Pair with Host 中选择 CLocation", attempt: attempt)
    }

    fileprivate func connected(attempt: PairingAttempt) {
        guard acceptsInteraction(attempt) else { return }
        interaction(kind: .confirmOnDevice, title: "请在系统设置中确认配对；如有提示，输入设备锁屏密码", attempt: attempt)
    }

    fileprivate func showPIN(_ pin: String, attempt: PairingAttempt) {
        guard acceptsInteraction(attempt), pin.count == 6, pin.allSatisfy(\.isNumber) else { return }
        interaction(kind: .displayCode, title: "将此验证码输入系统配对提示", code: pin, attempt: attempt)
        let content = UNMutableNotificationContent()
        content.title = "CLocation 配对验证码"
        content.body = pin
        let identifier = notificationIdentifier(attempt)
        let center = UNUserNotificationCenter.current()
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { [weak self] _ in
            Task { @MainActor in
                guard self?.acceptsInteraction(attempt) != true else { return }
                let center = UNUserNotificationCenter.current()
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
            }
        }
    }

    private func interaction(kind: WirePairingKind, title: String, code: String? = nil, attempt: PairingAttempt) {
        guard acceptsInteraction(attempt) else { return }
        let id = UUID().uuidString
        interactionIds.insert(id)
        onInteraction?(WirePairingInteraction(id: id, operationId: attempt.operationId,
            kind: kind, title: title, expiresAtMillis: expiresAtMillis, displayCode: code), attempt)
    }

    private func finish(_ result: Result<Data, NativeFailure>, attempt: PairingAttempt) {
        guard active, workerAttempt == attempt else { return }
        let outcome: Result<Void, NativeFailure>
        if cancelled { outcome = .failure(NativeFailure("cancelled", "配对已取消", "pairing.accept")) }
        else {
            do { try PairingVault.save(result.get()); outcome = .success(()) }
            catch { outcome = .failure(error as? NativeFailure ?? NativeFailure("secureStorageUnavailable", "配对记录保存失败", "pairing.keychain")) }
        }
        active = false
        interactionGate.invalidate()
        interactionIds.removeAll()
        teardown()
        workerAttempt = nil
        onFinished?(attempt.operationId, outcome)
        cancellationWaiters.forEach { $0.resume() }; cancellationWaiters.removeAll()
    }

    private func teardown() {
        advertiser.stop()
        let center = UNUserNotificationCenter.current()
        if let attempt = workerAttempt {
            let identifier = notificationIdentifier(attempt)
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid
        }
    }

    private func notificationIdentifier(_ attempt: PairingAttempt) -> String {
        "clocation.pairing.pin.\(attempt.token.uuidString)"
    }
}

private final class PairingCallbackBox: @unchecked Sendable {
    weak var owner: PairingCoordinator?
    let attempt: PairingAttempt
    init(owner: PairingCoordinator, attempt: PairingAttempt) { self.owner = owner; self.attempt = attempt }
}

private func clocationPIN(_ value: UnsafePointer<CChar>?, _ context: UnsafeMutableRawPointer?) {
    guard let value, let context else { return }
    let pin = String(cString: value)
    let box = Unmanaged<PairingCallbackBox>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in box.owner?.showPIN(pin, attempt: box.attempt) }
}

private func clocationConnected(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let box = Unmanaged<PairingCallbackBox>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in box.owner?.connected(attempt: box.attempt) }
}

private func clocationListening(_ port: UInt16, _ identifier: UnsafePointer<CChar>?,
    _ name: UnsafePointer<CChar>?, _ model: UnsafePointer<CChar>?, _ auth: UnsafePointer<CChar>?,
    _ version: UnsafePointer<CChar>?, _ minimum: UnsafePointer<CChar>?, _ context: UnsafeMutableRawPointer?) {
    guard let identifier, let name, let model, let auth, let version, let minimum, let context else { return }
    let values = [identifier, name, model, auth, version, minimum].map { String(cString: $0) }
    let box = Unmanaged<PairingCallbackBox>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in box.owner?.listening(port: port, values: values, attempt: box.attempt) }
}
