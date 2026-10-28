import Foundation
import LocalAuthentication
import Security

enum KeychainStore {
    static let productionService = "community.localworkspace.mac"
    private static let service = Bundle.main.bundleIdentifier?.hasSuffix(".preview") == true
        ? "community.localworkspace.mac.preview" : productionService
    private static var query: [String: Any] {
        query(for: service)
    }
    private static func query(for service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "tunnel-api-key"]
    }
    // A status-only lookup detects an existing item without requesting its
    // secret data or showing an authorization dialog.
    static func hasSavedKey(useProduction: Bool = false) -> Bool {
        var request = query(for: useProduction ? productionService : service)
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(request as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed
    }
    static func read(allowInteraction: Bool = true, useProduction: Bool = false) throws -> String? {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/workspace-credentials")
        if FileManager.default.isExecutableFile(atPath: helper.path) {
            let process = Process(), output = Pipe()
            process.executableURL = helper
            process.arguments = [useProduction ? "read-production" : "read", allowInteraction ? "interactive" : "noninteractive"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let response = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, response.count <= 65553,
                  let newline = response.firstIndex(of: 10), newline <= 16,
                  let status = Int32(String(decoding: response[..<newline], as: UTF8.self)) else {
                throw WorkspaceError(message: "凭据组件未返回有效结果，请重新安装应用。")
            }
            if status == errSecItemNotFound { return "" }
            if !allowInteraction && (status == errSecInteractionNotAllowed || status == errSecAuthFailed) { return nil }
            guard status == errSecSuccess else { throw WorkspaceError(message: "无法读取钥匙串：\(status)") }
            return String(decoding: response[response.index(after: newline)...], as: UTF8.self)
        }
        if Bundle.main.object(forInfoDictionaryKey: "LWCredentialHelperRequired") as? Bool == true {
            throw WorkspaceError(message: "凭据组件缺失，请重新安装应用。")
        }
        var request = query(for: useProduction ? productionService : service)
        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            request[kSecUseAuthenticationContext as String] = context
        }
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        if !allowInteraction && (status == errSecInteractionNotAllowed || status == errSecAuthFailed) { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw WorkspaceError(message: "无法读取钥匙串：\(status)")
        }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ value: String) throws {
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw WorkspaceError(message: "无法删除钥匙串项目：\(status)")
            }
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var request = query.merging(attributes) { _, new in new }
            request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(request as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WorkspaceError(message: "无法保存到钥匙串：\(status)") }
    }
}
