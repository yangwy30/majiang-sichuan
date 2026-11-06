import Foundation

/// 识别出的一张牌。两路识别（端侧模型 + Gemini）不一致时，`alternatives` 里放另一路的读法，让用户选。
public struct RecognizedTile: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var tile: Tile
    public var alternatives: [Tile]
    /// 另一路没读到这张（可能是多读了），没有候选也要用户看一眼。
    public var uncertain: Bool

    public init(id: UUID = UUID(), tile: Tile, alternatives: [Tile] = [], uncertain: Bool = false) {
        self.id = id
        self.tile = tile
        self.alternatives = alternatives
        self.uncertain = uncertain
    }

    public var needsReview: Bool { uncertain || !alternatives.isEmpty }
    /// 所有候选，当前读法在前。
    public var candidates: [Tile] { [tile] + alternatives.filter { $0 != tile } }
}

/// 一张照片的识别结果。
public struct Recognition: Hashable, Codable, Sendable {
    /// 立牌，从左到右，包括和的那张（放在最右）。
    public var concealed: [RecognizedTile]
    /// 摆在旁边的吃、碰、杠。
    public var melds: [Meld]
    public var flowerCount: Int
    /// 哪一路识别出来的，例如「Gemini」「端侧」「双读」。
    public var source: String
    /// 识别过程中的说明，例如「有一张牌没认出来」，显示在确认页。
    public var notes: [String] = []

    public init(concealed: [RecognizedTile], melds: [Meld] = [], flowerCount: Int = 0, source: String) {
        self.concealed = concealed
        self.melds = melds
        self.flowerCount = flowerCount
        self.source = source
    }

    public init(concealed tiles: [Tile], melds: [Meld] = [], flowerCount: Int = 0, source: String) {
        self.init(concealed: tiles.map { RecognizedTile(tile: $0) }, melds: melds, flowerCount: flowerCount, source: source)
    }

    /// 按当前读法组成的手牌，和张取最右一张。
    public var hand: Hand {
        let tiles = concealed.map(\.tile)
        return Hand(melds: melds, concealed: tiles, winningTile: tiles.last)
    }

    public var reviewCount: Int { concealed.filter(\.needsReview).count }
}

public struct RecognitionRequest: Sendable {
    public var image: Data
    public var mimeType: String
    /// 规则校验没通过时，带上上一次的结果和原因再问一次。
    public var previous: Recognition?
    public var feedback: String?

    public init(image: Data, mimeType: String = "image/jpeg", previous: Recognition? = nil, feedback: String? = nil) {
        self.image = image
        self.mimeType = mimeType
        self.previous = previous
        self.feedback = feedback
    }
}

public enum RecognitionError: Error, Hashable, Sendable {
    /// 这一路识别现在用不了（比如端侧模型没装）。
    case unavailable(String)
    /// 照片里没找到牌。
    case nothingFound
    /// 没有配置 API Key 或代理地址。
    case notConfigured
    case network(String)
    case badResponse(String)
    /// 中转站说邀请码有问题（没有、不对、停用了、手机绑满了）。App 收到就把存着的码清掉。
    case inviteRejected(String)

    public var message: String {
        switch self {
        case .unavailable(let why): why
        case .nothingFound: "照片里没找到牌，靠近一点、亮一点再拍"
        case .notConfigured: "还没有设置识别服务（在设置里填 Gemini API Key 或代理地址）"
        case .network(let why): "网络出错：\(why)"
        case .badResponse(let why): "识别结果看不懂：\(why)"
        case .inviteRejected(let why): why
        }
    }
}

/// 认牌。Gemini、端侧模型、假数据都实现这个协议，界面只认它。
public protocol TileRecognizer: Sendable {
    var name: String { get }
    func recognize(_ request: RecognitionRequest) async throws -> Recognition
}

/// 能先给一个快的结果、过一会儿再给最终结果的识别（双读：端侧先出，Gemini 复核完再合并）。
public protocol ProgressiveTileRecognizer: TileRecognizer {
    /// 快的结果一出来就调 `preview`（可能不调，比如端侧没认出来），最后返回最终结果。
    func recognize(_ request: RecognitionRequest,
                   preview: @escaping @Sendable (Recognition) async -> Void) async throws -> Recognition
}

// MARK: - 端侧模型

/// 端侧认牌：检测模型找出每张牌，`TileLayout` 去掉画面里别人的牌、排成手牌。几十到几百毫秒出结果，不用联网。
/// 分不出吃碰杠（都当立牌），双读时副露以 Gemini 为准。
/// 模型见 `CoreMLTileDetector`。
public struct OnDeviceRecognizer: TileRecognizer {
    public let name = "端侧"
    public var detector: TileDetecting?

    /// `detector` 为 nil 表示这台设备上没装模型。
    public init(detector: TileDetecting? = nil) {
        self.detector = detector
    }

    public func recognize(_ request: RecognitionRequest) async throws -> Recognition {
        guard let detector else { throw RecognitionError.unavailable("端侧模型没装（见 app/README.md）") }
        let recognition = TileLayout.recognition(from: try await detector.detect(in: request.image))
        guard !recognition.concealed.isEmpty else { throw RecognitionError.nothingFound }
        return recognition
    }
}

// MARK: - 假数据

/// 开发和演示用：不看照片，按顺序返回预设的手牌。
public struct MockRecognizer: TileRecognizer {
    public let name: String
    public var samples: [Recognition]
    public var delay: Duration
    private let counter = Counter()

    public init(name: String = "演示", samples: [Recognition] = MockRecognizer.defaultSamples, delay: Duration = .milliseconds(800)) {
        self.name = name
        self.samples = samples
        self.delay = delay
    }

    public func recognize(_ request: RecognitionRequest) async throws -> Recognition {
        try await Task.sleep(for: delay)
        guard !samples.isEmpty else { throw RecognitionError.unavailable("没有演示数据") }
        return samples[counter.next() % samples.count]
    }

    /// 清一色（mockup 里那手）带一张两路读得不一样的牌；一手带碰和暗杠的；一手不成和、需要改牌的。
    public static let defaultSamples: [Recognition] = {
        var flush = Recognition(concealed: Tile.parseList("1112233445566p 7p"), source: "演示")
        flush.concealed[9] = RecognizedTile(tile: Tile(.dots, 5), alternatives: [Tile(.dots, 4)])

        let melded = Recognition(
            concealed: Tile.parseList("123m 567m 中中"),
            melds: [.pung(Tile(.honors, 1)), .kong(Tile(.characters, 9), concealed: true)],
            flowerCount: 2, source: "演示")

        let misread = Recognition(concealed: Tile.parseList("234m 456p 567s 234s 5m 6m"), source: "演示")
        return [flush, melded, misread]
    }()

    private final class Counter: @unchecked Sendable {
        private var value = 0
        private let lock = NSLock()
        func next() -> Int {
            lock.lock(); defer { lock.unlock() }
            defer { value += 1 }
            return value
        }
    }
}
