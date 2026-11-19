import Foundation
import Darwin
import IdeviceRuntime

struct NativeFailure: Error {
    let code: String
    let message: String
    let stage: String
    init(_ code: String, _ message: String, _ stage: String) {
        self.code = code; self.message = message; self.stage = stage
    }
    static func check(_ error: UnsafeMutablePointer<IdeviceFfiError>?, stage: String) throws {
        guard let error else { return }
        let code = error.pointee.code
        // Never expose peer error strings: some contain device IDs or pairing material.
        let text = error.pointee.message.map { String(cString: $0).lowercased() } ?? ""
        defer { idevice_error_free(error) }
        if code == 27 { throw NativeFailure("cancelled", "操作已取消", stage) }
        if text.contains("timeout") || text.contains("timed out") || text.contains("timedout") {
            throw NativeFailure("timeout", "设备服务超时；定位效果未知，请重新连接后清除", stage)
        }
        let category = stage.hasPrefix("pairing") ? "pairingFailed" :
            (stage.hasPrefix("dvt") ? "developerServiceUnavailable" : "tunnelUnavailable")
        throw NativeFailure(category, "设备服务操作失败（原生错误码 \(code)）", stage)
    }
}

/// All methods and pointers are confined to LocationRuntime.engineQueue.
/// Adapted from MIT Locus/Aurora; see native/idevice/PROVENANCE.md.
final class IdeviceEngine: @unchecked Sendable {
    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var server: OpaquePointer?
    private var simulation: OpaquePointer?
    var isConnected: Bool { simulation != nil }

    func connect() throws {
        if isConnected { return }
        guard let data = try PairingVault.load() else {
            throw NativeFailure("pairingRequired", "请先完成系统本机配对", "pairing.load")
        }
        idevice_set_global_timeout(10)
        var pairing: OpaquePointer?
        try data.withUnsafeBytes { buffer in
            try NativeFailure.check(rp_pairing_file_from_bytes(
                buffer.bindMemory(to: UInt8.self).baseAddress, UInt(data.count), &pairing), stage: "pairing.parse")
        }
        guard let pairing else { throw NativeFailure("pairingFailed", "配对记录无效", "pairing.parse") }
        defer { rp_pairing_file_free(pairing) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        _ = "10.7.0.1".withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        do {
            try withUnsafePointer(to: &address) { pointer in
                try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    try NativeFailure.check(tunnel_create_rppairing($0,
                        socklen_t(MemoryLayout<sockaddr_in>.size), "CLocation", pairing,
                        nil, nil, &adapter, &handshake), stage: "tunnel.pairingVerify")
                }
            }
            try NativeFailure.check(remote_server_connect_rsd(adapter, handshake, &server), stage: "dvt.connect")
            try NativeFailure.check(location_simulation_new(server, &simulation), stage: "dvt.locationService")
        } catch { disconnect(); throw error }
    }

    func set(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw NativeFailure("invalidCoordinate", "请输入有效 WGS84 经纬度", "dvt.set")
        }
        guard let simulation else { throw NativeFailure("notConnected", "请先连接设备服务", "dvt.set") }
        do { try NativeFailure.check(location_simulation_set(simulation, latitude, longitude), stage: "dvt.set") }
        catch { disconnect(); throw error }
        // The pinned patch writes a DVT message without waiting for an ACK.
        // Returning without an FFI error proves only SENT, never ACKNOWLEDGED.
    }

    func clear() throws {
        // Recovery is allowed to establish a new connection; it never replays set.
        if !isConnected { try connect() }
        guard let simulation else { throw NativeFailure("notConnected", "设备服务尚未连接", "dvt.clear") }
        do { try NativeFailure.check(location_simulation_clear(simulation), stage: "dvt.clear") }
        catch { disconnect(); throw error }
    }

    func disconnect() {
        // LocationSimulation borrows RemoteServer; free in reverse dependency order.
        if let simulation { location_simulation_free(simulation) }; simulation = nil
        if let server { remote_server_free(server) }; server = nil
        if let handshake { rsd_handshake_free(handshake) }; handshake = nil
        if let adapter { adapter_free(adapter) }; adapter = nil
    }
    deinit { disconnect() }
}
