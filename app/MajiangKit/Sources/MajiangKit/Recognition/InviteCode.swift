import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// AI 认牌是邀请制：用户在 App 里填码，中转站查码、把这台手机绑上（见 server/README.md「邀请码」）。
/// 挡人靠服务器，这里只是先把格式理一理，再问一下中转站码对不对。
public enum InviteCode {
    /// 和服务器一样：去掉 0 O 1 I，6 位。
    public static let alphabet = Set("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    public static let length = 6

    /// 用户输入的码：不分大小写，空格、横线忽略。格式不对返回 nil。
    public static func normalize(_ input: String) -> String? {
        let code = String(input.uppercased().filter { !$0.isWhitespace && $0 != "-" })
        guard code.count == length, code.allSatisfy(alphabet.contains) else { return nil }
        return code
    }

    /// 中转站认牌地址旁边的填码地址：…/recognize → …/invite。
    public static func redeemURL(forProxy proxy: URL) -> URL {
        proxy.deletingLastPathComponent().appendingPathComponent("invite")
    }

    public struct Redemption: Equatable, Sendable, Decodable {
        public var code: String
        public var dailyLimit: Int
        public var remaining: Int
    }

    /// 问中转站这个码能不能用，能用就把这台手机绑上。失败时抛 `RecognitionError`，message 可以直接给用户看。
    public static func redeem(_ input: String, proxy: URL, deviceID: String,
                              http: HTTPClient = URLSessionHTTPClient()) async throws -> Redemption {
        guard let code = normalize(input) else {
            throw RecognitionError.inviteRejected("邀请码是 6 位字母和数字，核对一下再输")
        }
        var request = URLRequest(url: redeemURL(forProxy: proxy))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Majiang-Device")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])

        let data: Data
        let status: Int
        do {
            (data, status) = try await http.send(request)
        } catch {
            throw RecognitionError.network(error.localizedDescription)
        }
        guard status == 200 else {
            if let refusal = GeminiRecognizer.proxyRefusal(data) {
                throw refusal.invite ? RecognitionError.inviteRejected(refusal.message) : RecognitionError.unavailable(refusal.message)
            }
            throw RecognitionError.network("HTTP \(status)")
        }
        guard let redemption = try? JSONDecoder().decode(Redemption.self, from: data) else {
            throw RecognitionError.badResponse("填码的回答看不懂")
        }
        return redemption
    }
}

/// 包一层：认牌时中转站说码有问题，就通知 App 清掉存着的码（下次拍照页会提示重新输入），错误照常往外抛。
public struct InviteCheckedRecognizer: TileRecognizer {
    public var base: TileRecognizer
    public var onRejected: @Sendable () async -> Void

    public init(base: TileRecognizer, onRejected: @escaping @Sendable () async -> Void) {
        self.base = base
        self.onRejected = onRejected
    }

    public var name: String { base.name }

    public func recognize(_ request: RecognitionRequest) async throws -> Recognition {
        do {
            return try await base.recognize(request)
        } catch RecognitionError.inviteRejected(let message) {
            await onRejected()
            throw RecognitionError.inviteRejected(message)
        }
    }
}
