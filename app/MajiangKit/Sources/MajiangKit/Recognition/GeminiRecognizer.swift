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
        /// 代理收到的请求体和 Google generateContent 一样，原样转发。deviceID 用来按手机限每天的次数。
        /// inviteCode：AI 认牌是邀请制，码由中转站校验（见 server/README.md「邀请码」）。
        case proxy(url: URL, token: String? = nil, deviceID: String? = nil, inviteCode: String? = nil)
    }

    public var endpoint: Endpoint
    /// 研究阶段只用 Flash（Yang 的决定），见 research/gemini-recognition.md。
    public var model: String
    /// 牌面参考图。研究里「参考图 + 数点数」是最好的方法（33 张里 32 张全对）。
    /// 注意：研究用的参考图没有许可证，不能打包进 App，这里要用我们自己画的牌面。
    public var referenceSheet: (data: Data, mimeType: String)?
    /// 思考深度（Gemini 3 的 thinkingLevel）。研究里 3.8 Flash 调成 low：33 张里 30 张全对（默认 32 张），
    /// 第一次调用平均从二十多秒降到 7 秒，见 research/gemini-recognition.md。3.8 Flash 不支持 minimal。
    /// nil 用模型默认。走中转站时以服务器的设置为准。
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

/// 用 Gemini 认牌。只让模型读牌，和没和、几番由规则引擎决定。
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
            parts.append(["text": "参考图：34 种牌的简化画法，下面标了记法，用来对照花色和点数。真实的牌画法会不同：1条常画成一只鸟，8条常画成 W/M 形，以照片里数出的竹节、圆点数为准。"])
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

    /// 基于研究里效果最好的提示词（tools/gemini-test 的 PROMPT + PIP_HINT），改成按 App 的拍照约定分开立牌和副露。
    static let prompt = """
    这是一张麻将照片，拍的是和牌那家的牌：手牌推倒排成一排，和的那张放在最右；吃、碰、杠放在旁边，暗杠翻开一张。
    请逐张读出这家的牌。
    - 不要算进别人的牌、打出去的牌（牌河）、牌墙和桌上其他散牌。
    - 记法：1m-9m=万子，1p-9p=饼/筒子，1s-9s=条/索子，字牌用汉字：东 南 西 北 中 发 白。
    - concealed：排成一排的手牌，从左到右，包括最右边和的那张。
    - melds：摆在旁边的每一组吃、碰、杠。kind 写 chow（吃）、pung（碰）、kong（明杠）或 concealed_kong（暗杠）；杠写满 4 张，扣着的那张也算作这张杠牌。
    - 花牌（春夏秋冬梅兰竹菊）不要放进牌里，只在 flowers 里报数量。
    特别注意：条子和饼子要逐张数点数，不要凭整体印象猜。
    - 条子数竹节根数：1条通常画成一只鸟；5条是四角各一根 + 中间一根（中间那根常是红色）；4条是两列各两根、中间没有；6条是两排各三根；7条是顶上一根 + 下面六根；8条常画成 W/M 形；9条是三排各三根。
    - 饼子数圆点：6饼是上面 2 个 + 下面 4 个；7饼是斜着 3 个 + 下面 4 个；8饼是两列各 4 个。
    - 每张先数清楚再写，写完确认张数：立牌 + 每组副露 3 张（杠 4 张）一般共 14 张，每个杠多 1 张。
    不要判断和没和，只输出 JSON。
    """

    /// 34 种牌的记法，限定模型只能输出这些。
    static let tileNotations: [String] = Tile.all.map(\.notation)

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "concealed": ["type": "ARRAY", "items": ["type": "STRING", "enum": tileNotations],
                          "description": "Standing tiles left to right, winning tile last, e.g. 1m, 5p, 9s, 东"],
            "melds": ["type": "ARRAY", "items": [
                "type": "OBJECT",
                "properties": [
                    "kind": ["type": "STRING", "enum": ["chow", "pung", "kong", "concealed_kong"]],
                    "tiles": ["type": "ARRAY", "items": ["type": "STRING", "enum": tileNotations]],
                ],
                "required": ["kind", "tiles"],
            ]],
            "flowers": ["type": "INTEGER"],
            "confidence": ["type": "STRING", "enum": ["high", "medium", "low"]],
        ],
        "required": ["concealed", "melds", "flowers"],
    ]

    // MARK: 回答

    /// 代理自己拒绝的请求（比如今天的次数用完了）带一句给用户看的话：{"error":{"message":…,"majiang":true}}。
    /// 是邀请码的问题时多一个 "invite": true。
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

    /// 解析模型的 JSON。读不懂的牌不让整次识别失败：花牌名记进花牌数，其他的丢掉并记一条说明，
    /// 张数不对时确认页会提示补牌；拼不成一组的副露拆回立牌，标成待确认。
    static func parseAnswer(_ data: Data) throws -> Recognition {
        let answer: Answer
        do {
            answer = try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw RecognitionError.badResponse("JSON 格式不对")
        }

        var flowers = max(0, answer.flowers ?? 0)
        var notes: [String] = []
        func read(_ tokens: [String]) -> [Tile] {
            tokens.compactMap { token in
                if let tile = Tile(notation: token) { return tile }
                if let first = token.first, flowerNames.contains(first) {
                    flowers += 1
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
                // 暗杠扣着的牌模型有时只报 3 张，按类型认成杠
                melds.append(.kong(tiles[0], concealed: m.kind == "concealed_kong"))
            } else if let meld = Meld.from(tiles: tiles, concealedKong: m.kind == "concealed_kong") {
                melds.append(meld)
            } else {
                notes.append("有一组吃碰杠拼不成（\(m.tiles.joined(separator: " "))），放回手牌里请确认")
                concealed.insert(contentsOf: tiles.map { RecognizedTile(tile: $0, uncertain: true) }, at: 0)
            }
        }
        var recognition = Recognition(concealed: concealed, melds: melds, flowerCount: flowers, source: "Gemini")
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
            flowers: recognition.flowerCount)
        let data = (try? JSONEncoder().encode(answer)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
