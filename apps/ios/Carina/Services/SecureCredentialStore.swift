import Foundation
import Security

protocol SecureCredentialStoring: Sendable {
    func save(_ value: String, account: String) async throws
    func load(account: String) async throws -> String?
    func delete(account: String) async throws
}

enum CredentialStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            "Keychain operation failed with status \(status)."
        case .invalidData:
            "The saved Keychain value is invalid."
        }
    }
}

actor SecureCredentialStore: SecureCredentialStoring {
    static let shared = SecureCredentialStore()

    private let service = "com.leandrofajardo.carina.credentials"

    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(updateStatus)
        }
        var insert = query
        attributes.forEach { insert[$0.key] = $0.value }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(addStatus)
        }
    }

    func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidData
        }
        return value
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

@MainActor
final class CredentialManager: ObservableObject {
    static let bridgeTokenAccount = "bridge-token"

    @Published var bridgeToken = ""
    @Published private(set) var hasBridgeToken = false
    @Published private(set) var errorMessage: String?

    private let store: SecureCredentialStoring

    init(store: SecureCredentialStoring = SecureCredentialStore.shared) {
        self.store = store
        Task { await load() }
    }

    func load() async {
        do {
            bridgeToken = try await store.load(account: Self.bridgeTokenAccount) ?? ""
            hasBridgeToken = !bridgeToken.isEmpty
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func save() async -> Bool {
        let clean = bridgeToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 32 else {
            errorMessage = "The bridge token must contain at least 32 characters."
            return false
        }
        do {
            try await store.save(clean, account: Self.bridgeTokenAccount)
            bridgeToken = clean
            hasBridgeToken = true
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete() async {
        do {
            try await store.delete(account: Self.bridgeTokenAccount)
            bridgeToken = ""
            hasBridgeToken = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
