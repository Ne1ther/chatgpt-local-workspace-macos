import Foundation

/// Secrets live only for this GUI process. Reconnecting must not reread Keychain.
@MainActor
final class ConnectionCredentialCache {
    private var values: [Bool: String] = [:]

    func resolve(useProduction: Bool, read: @escaping @Sendable (Bool) throws -> String?) async throws -> String {
        if let value = values[useProduction] { return value }
        let value = try await Task.detached { try read(useProduction) ?? "" }.value
        try Task.checkCancellation()
        if !value.isEmpty { values[useProduction] = value }
        return value
    }

    func remember(_ value: String, useProduction: Bool) {
        if value.isEmpty { values.removeValue(forKey: useProduction) }
        else { values[useProduction] = value }
    }

    func redacted(_ text: String) -> String {
        values.values.reduce(text) { $0.replacingOccurrences(of: $1, with: "[redacted]") }
    }
}
