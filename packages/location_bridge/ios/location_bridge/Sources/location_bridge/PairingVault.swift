import Foundation
import Security
import IdeviceRuntime

/// Pairing credentials never cross the Flutter boundary or touch an unprotected file.
enum PairingVault {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.clocation.location-bridge.pairing",
         kSecAttrAccount as String: "remote-pairing-v1"]
    }

    static func load() throws -> Data? {
        var item: CFTypeRef?
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw NativeFailure("secureStorageUnavailable", "无法读取本机受保护的配对记录", "pairing.keychain")
        }
        return data
    }

    static func save(_ data: Data) throws {
        let values: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            values.forEach { insert[$0.key] = $0.value }
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw NativeFailure("secureStorageUnavailable", "无法安全保存配对记录", "pairing.keychain")
            }
        } else if status != errSecSuccess {
            throw NativeFailure("secureStorageUnavailable", "无法更新配对记录", "pairing.keychain")
        }
    }

    static func serialize(_ handle: OpaquePointer) throws -> Data {
        var bytes: UnsafeMutablePointer<UInt8>?
        var count = 0
        try NativeFailure.check(rp_pairing_file_to_bytes(handle, &bytes, &count), stage: "pairing.serialize")
        guard let bytes, count > 0 else { throw NativeFailure("pairingFailed", "未返回有效配对记录", "pairing.serialize") }
        defer { idevice_data_free(bytes, UInt(count)) }
        return Data(bytes: bytes, count: count)
    }
}
