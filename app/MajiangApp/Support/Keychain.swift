import Foundation
import Security
import MajiangKit

/// Gemini API Key 存在钥匙串里。只在开发阶段用；上架后走后端代理，App 里不放 Key。
struct GeminiKeychain: APIKeyProvider {
    private static let service = "majiang-ppc.gemini"
    private static let account = "api-key"

    func apiKey() throws -> String {
        guard let key = Self.read(), !key.isEmpty else { throw RecognitionError.notConfigured }
        return key
    }

    static var hasKey: Bool { !(read() ?? "").isEmpty }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

#if DEBUG
extension GeminiKeychain {
    /// 开发版：编译前把 Mac 上的 Key 放到 Resources/DevSecrets/GeminiDevKey.txt（不进仓库，见 app/README.md），
    /// 装到手机后第一次打开自动存进钥匙串，不用在设置里粘贴。钥匙串里已经有 Key 就不动。
    static func importBundledDevKey() {
        guard !hasKey,
              let url = Bundle.main.url(forResource: "GeminiDevKey", withExtension: "txt"),
              let key = try? String(contentsOf: url, encoding: .utf8) else { return }
        save(key)
    }
}
#endif

/// 这台手机的随机编号，发给后端代理按手机限每天的识别次数。存钥匙串，删了 App 重装也不变；不含任何个人信息。
enum DeviceID {
    private static let service = "majiang-ppc.device"
    private static let account = "id"

    static let current: String = {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let id = String(data: data, encoding: .utf8), UUID(uuidString: id) != nil {
            return id
        }
        let id = UUID().uuidString
        var add = base
        add[kSecValueData as String] = Data(id.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        return id
    }()
}

/// 用户填好的 AI 认牌邀请码（中转站已经确认过）。存钥匙串，只在这台手机上。
enum InviteKeychain {
    private static let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "majiang-ppc.invite",
        kSecAttrAccount as String: "code",
    ]

    static func read() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let code = String(data: data, encoding: .utf8), !code.isEmpty else { return nil }
        return code
    }

    /// nil 就是删掉。
    static func save(_ code: String?) {
        SecItemDelete(base as CFDictionary)
        guard let code, !code.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(code.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
