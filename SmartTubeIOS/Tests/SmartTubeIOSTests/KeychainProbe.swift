import Foundation
import Security

/// Whether this test process can write to the Keychain. A package test bundle that runs
/// without a host app gets `errSecMissingEntitlement` (-34018) in the Simulator, so
/// Keychain round-trip tests are skipped there instead of failing for environmental reasons.
enum KeychainProbe {
    static let status: OSStatus = {
        let service = "keychain-probe-\(UUID().uuidString)"
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "probe",
            kSecValueData: Data("probe".utf8),
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
        return status
    }()

    static var isAvailable: Bool { status == errSecSuccess }
}
