import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 发 HTTP 请求。单独抽出来，测试时可以换成假的。
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// 取 API Key。App 里从钥匙串读，Key 绝不写进代码或仓库。
public protocol APIKeyProvider: Sendable {
    func apiKey() throws -> String
}

public struct GeminiConfiguration: Sendable {
    public enum Endpoint: Sendable {
        /// 开发阶段：App 直接调 Google，Key 由用户在设置里填，存在钥匙串。
        case direct(APIKeyProvider)
        /// 上架后：调我们自己的后端代理（server/，Cloudflare Worker），代理持有 Key，App 里没有 Key。
        case proxy(url: URL, token: String? = nil, deviceID: String? = nil, inviteCode: String? = nil)
    }

    public var endpoint: Endpoint
    public var model: String
    public var referenceSheet: (data: Data, mimeType: String)?
    public var thinkingLevel: String?
    public var timeout: TimeInterval

    public init(endpoint: Endpoint, model: String = "gemini-3.8-flash",
                referenceSheet: (data: Data, mimeType: String)? = nil, thinkingLevel: String? = "low",
                timeout: TimeInterval = 60) {
        self.endpoint = endpoint
        self.model = model
        self.referenceSheet = referenceSheet
        self.thinkingLevel = thinkingLevel
        self.timeout = timeout
    }
}

/// 用 Gemini 认牌。只让模型读牌，和没和、几番由川麻规则引擎决定。
public struct GeminiRecognizer: TileRecognizer {
    public let name = "Gemini"
    public var configuration: GeminiConfiguration
    public var http: HTTPClient

    public init(configuration: GeminiConfiguration, http: HTTPClient = URLSessionHTTPClient()) {
        self.configuration = configuration
        self.http = http
    }

    static let apiBase = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    public func recognize(_ request: RecognitionRequest) async throws -> Recognition {
        let urlRequest = try makeURLRequest(for: request)
        let data: Data
        let status: Int
        do {
            (data, status) = try await http.send(urlRequest)
        } catch {
            throw RecognitionError.network(error.localizedDescription)
        }
        guard status == 200 else {
            if let refusal = Self.proxyRefusal(data) {
                throw refusal.invite ? RecognitionError.inviteRejected(refusal.message) : RecognitionError.unavailable(refusal.message)
            }
            let text = String(decoding: data.prefix(300), as: UTF8.self)
            throw RecognitionError.network("HTTP \(status) \(text)")
        }
        return try Self.parseResponse(data)
    }

    // MARK: 请求

    func makeURLRequest(for request: RecognitionRequest) throws -> URLRequest {
        var urlRequest: URLRequest
        switch configuration.endpoint {
        case .direct(let keys):
            let key = try keys.apiKey()
            guard !key.isEmpty else { throw RecognitionError.notConfigured }
            urlRequest = URLRequest(url: Self.apiBase.appendingPathComponent("models/\(configuration.model):generateContent"))
            urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .proxy(let url, let token, let deviceID, let inviteCode):
            urlRequest = URLRequest(url: url)
            urlRequest.setValue(configuration.model, forHTTPHeaderField: "X-Majiang-Model")
            if let deviceID { urlRequest.setValue(deviceID, forHTTPHeaderField: "X-Majiang-Device") }
            if let inviteCode { urlRequest.setValue(inviteCode, forHTTPHeaderField: "X-Majiang-Invite") }
            if let token { urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        }
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody(for: request))
        return urlRequest
    }

    func requestBody(for request: RecognitionRequest) -> [String: Any] {
        var parts: [[String: Any]] = []
        if let sheet = configuration.referenceSheet {
            parts.append(["text": "参考图：四川麻将 27 种序数牌（万、条、筒）的简化画法，下面标了记法，用来对照花色和点数。真实的牌画法会不同：1条常画成一只鸟，8条常画成 W/M 形，以照片里数出的竹节、圆点数为准。"])
            parts.append(Self.imagePart(sheet.data, sheet.mimeType))
            parts.append(["text": "要识别的照片："])
        }
        parts.append(Self.imagePart(request.image, request.mimeType))
        parts.append(["text": Self.prompt])

        var contents: [[String: Any]] = [["role": "user", "parts": parts]]
        if let previous = request.previous, let feedback = request.feedback {
            contents.append(["role": "model", "parts": [["text": Self.encodeAnswer(previous)]]])
            contents.append(["role": "user", "parts": [["text": feedback + "\n请对照照片逐张重新数点数，再输出一次 JSON。"]]])
        }
        var generationConfig: [String: Any] = ["responseMimeType": "application/json", "responseSchema": Self.schema]
        if let level = configuration.thinkingLevel {
            generationConfig["thinkingConfig"] = ["thinkingLevel": level]
        }
        return ["contents": contents, "generationConfig": generationConfig]
    }

    static func imagePart(_ data: Data, _ mimeType: String) -> [String: Any] {
        ["inline_data": ["mime_type": mimeType, "data": data.base64EncodedString()]]
    }

    /// 四川麻将专用提示词：限定 108 张万筒条序数牌，无字牌无花牌，无吃牌，支持 14 张胡牌或 13 张查大叫。
    static let prompt = """
    这是一张四川麻将照片，拍的是玩家推倒的一排手牌（胡牌时立牌+副露共 14 张，流局查叫时共 13 张，每个杠多 1 张）：手牌排成一排，胡的那张放在最右；碰、杠放在旁边，暗杠翻开一张。
    请逐张读出这家的牌。
    - 四川麻将只有万、筒（饼）、条（索）三门序数牌（共 108 张），绝对没有东南西北中发白字牌，也没有花牌，并且不能吃牌（只有碰、明杠、暗杠）。
    - 不要算进别人的牌、打出去的牌（牌河）、牌墙和桌上其他散牌。
    - 记法：1m-9m=万子，1p-9p=筒/饼子，1s-9s=条/索子。
    - concealed：排成一排的手牌，从左到右，包括最右边胡的那张。
    - melds：摆在旁边的每一组碰、杠。kind 写 pung（碰）、kong（明杠/巴杠）或 concealed_kong（暗杠）；杠写满 4 张，扣着的那张也算作这张杠牌。
    特别注意：条子和筒子要逐张数点数，不要凭整体印象猜。
    - 条子数竹节根数：1条通常画成一只鸟；5条是四角各一根 + 中间一根（中间那根常是红色）；4条是两列各两根、中间没有；6条是两排各三根；7条是顶上一根 + 下面六根；8条常画成 W/M 形；9条是三排各三根。
    - 筒子数圆点：1筒是一个大圆饼（切勿误认为白板或花牌）；2筒是上下两个圆（切勿误认为字牌）；6筒是上面 2 个 + 下面 4 个；7筒是斜着 3 个 + 下面 4 个；8筒是两列各 4 个。
    不要判断胡没胡，只输出 JSON。
    """

    /// 27 种川麻序数牌记法，限定模型只能输出万、条、筒。
    static let tileNotations: [String] = Tile.all.map(\.notation)

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "concealed": ["type": "ARRAY", "items": ["type": "STRING", "enum": tileNotations],
                          "description": "Standing tiles left to right, winning tile last, e.g. 1m, 5p, 9s"],
            "melds": ["type": "ARRAY", "items": [
                "type": "OBJECT",
                "properties": [
                    "kind": ["type": "STRING", "enum": ["pung", "kong", "concealed_kong"]],
                    "tiles": ["type": "ARRAY", "items": ["type": "STRING", "enum": tileNotations]],
                ],
                "required": ["kind", "tiles"],
            ]],
            "flowers": ["type": "INTEGER"],
            "confidence": ["type": "STRING", "enum": ["high", "medium", "low"]],
        ],
        "required": ["concealed", "melds"],
    ]

    // MARK: 回答

    static func proxyRefusal(_ data: Data) -> (message: String, invite: Bool)? {
        struct Body: Decodable {
            struct Err: Decodable {
                var message: String
                var majiang: Bool?
                var invite: Bool?
            }
            var error: Err
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), body.error.majiang == true else { return nil }
        return (body.error.message, body.error.invite == true)
    }

    struct Answer: Codable {
        struct MeldAnswer: Codable {
            var kind: String
            var tiles: [String]
        }
        var concealed: [String]
        var melds: [MeldAnswer]?
        var flowers: Int?
        var confidence: String?
    }

    static func parseResponse(_ data: Data) throws -> Recognition {
        struct Envelope: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        var text: String?
                        var thought: Bool?
                    }
                    var parts: [Part]?
                }
                var content: Content?
                var finishReason: String?
            }
            struct PromptFeedback: Decodable {
                var blockReason: String?
            }
            var candidates: [Candidate]?
            var promptFeedback: PromptFeedback?
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw RecognitionError.badResponse("识别服务的回答格式不对")
        }
        if let reason = envelope.promptFeedback?.blockReason {
            throw RecognitionError.badResponse("这张照片没法识别（\(reason)），换一张试试")
        }
        guard let candidate = envelope.candidates?.first else {
            throw RecognitionError.badResponse("没有候选回答")
        }
        let text = (candidate.content?.parts ?? []).filter { $0.thought != true }.compactMap(\.text).joined()
        guard !text.isEmpty else {
            throw RecognitionError.badResponse("回答是空的（\(candidate.finishReason ?? "原因不明")），再拍一次试试")
        }
        return try parseAnswer(Data(text.utf8))
    }

    static let flowerNames: Set<Character> = ["春", "夏", "秋", "冬", "梅", "兰", "竹", "菊", "花"]

    /// 解析模型的 JSON。过滤字牌与花牌；川麻不能吃牌，若模型把顺子放进 melds，自动归入手牌。
    static func parseAnswer(_ data: Data) throws -> Recognition {
        let answer: Answer
        do {
            answer = try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw RecognitionError.badResponse("JSON 格式不对")
        }

        var notes: [String] = []
        func read(_ tokens: [String]) -> [Tile] {
            tokens.compactMap { token in
                if let tile = Tile(notation: token) {
                    if tile.isHonor {
                        notes.append("川麻没有字牌（\(token)），已自动忽略")
                        return nil
                    }
                    return tile
                }
                if let first = token.first, flowerNames.contains(first) {
                    return nil
                } else {
                    notes.append("有一张牌没认出来（\(token)）")
                }
                return nil
            }
        }

        var concealed = read(answer.concealed).map { RecognizedTile(tile: $0) }
        var melds: [Meld] = []
        for m in answer.melds ?? [] {
            let tiles = read(m.tiles)
            let isKong = m.kind == "kong" || m.kind == "concealed_kong"
            if isKong, (3...4).contains(tiles.count), Set(tiles).count == 1 {
                melds.append(.kong(tiles[0], concealed: m.kind == "concealed_kong"))
            } else if let meld = Meld.from(tiles: tiles, concealedKong: m.kind == "concealed_kong") {
                melds.append(meld)
            } else if !tiles.isEmpty {
                notes.append("有一组碰杠拼不成（\(m.tiles.joined(separator: " "))），放回手牌里请确认")
                concealed.insert(contentsOf: tiles.map { RecognizedTile(tile: $0, uncertain: true) }, at: 0)
            }
        }
        var recognition = Recognition(concealed: concealed, melds: melds, flowerCount: 0, source: "Gemini")
        recognition.notes = notes
        return recognition
    }

    static func encodeAnswer(_ recognition: Recognition) -> String {
        let answer = Answer(
            concealed: recognition.concealed.map(\.tile.notation),
            melds: recognition.melds.map { meld in
                let kind = meld.kind == .kong ? (meld.isConcealed ? "concealed_kong" : "kong") : meld.kind.rawValue
                return Answer.MeldAnswer(kind: kind, tiles: meld.tiles.map(\.notation))
            },
            flowers: 0)
        let data = (try? JSONEncoder().encode(answer)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
