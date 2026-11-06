import Foundation

/// 花色。raw value 与算番库的编码一致（高 4 位）。
public enum Suit: Int, Codable, CaseIterable, Sendable {
    case characters = 1  // 万
    case bamboo = 2      // 条
    case dots = 3        // 饼
    case honors = 4      // 字

    /// 记法后缀：m 万、s 条、p 饼、z 字。
    public var letter: Character {
        switch self {
        case .characters: "m"
        case .bamboo: "s"
        case .dots: "p"
        case .honors: "z"
        }
    }

    public var chineseName: String {
        switch self {
        case .characters: "万"
        case .bamboo: "条"
        case .dots: "饼"
        case .honors: "字"
        }
    }
}

/// 一张牌（不含花牌，花牌只计数量）。
public struct Tile: Hashable, Comparable, Sendable {
    public let suit: Suit
    /// 数牌 1–9；字牌 1 东 2 南 3 西 4 北 5 中 6 发 7 白。
    public let rank: Int

    public init?(suit: Suit, rank: Int) {
        let maxRank = suit == .honors ? 7 : 9
        guard (1...maxRank).contains(rank) else { return nil }
        self.suit = suit
        self.rank = rank
    }

    init(_ suit: Suit, _ rank: Int) {
        self.init(suit: suit, rank: rank)!
    }

    /// 全部 34 种牌，按万、条、饼、字排序。
    public static let all: [Tile] = Suit.allCases.flatMap { suit in
        (1...(suit == .honors ? 7 : 9)).map { Tile(suit, $0) }
    }

    public static func < (lhs: Tile, rhs: Tile) -> Bool {
        (lhs.suit.rawValue, lhs.rank) < (rhs.suit.rawValue, rhs.rank)
    }

    // MARK: 分类

    public var isHonor: Bool { suit == .honors }
    public var isNumbered: Bool { suit != .honors }
    public var isSuited: Bool { suit != .honors }
    public var isTerminal: Bool { isNumbered && (rank == 1 || rank == 9) }
    public var isTerminalOrHonor: Bool { isHonor || isTerminal }
    public var isSimple: Bool { isNumbered && (2...8).contains(rank) }
    public var isWind: Bool { isHonor && rank <= 4 }
    public var isDragon: Bool { isHonor && rank >= 5 }

    /// 同花色的下一张数牌（9 之后没有）。
    public var next: Tile? { isNumbered ? Tile(suit: suit, rank: rank + 1) : nil }

    // MARK: 编码

    /// 算番库的牌编码：高 4 位花色，低 4 位点数。
    public var code: UInt8 { UInt8(suit.rawValue << 4 | rank) }

    public init?(code: UInt8) {
        guard let suit = Suit(rawValue: Int(code >> 4)) else { return nil }
        self.init(suit: suit, rank: Int(code & 0xF))
    }

    // MARK: 文字

    static let honorNames = ["东", "南", "西", "北", "中", "发", "白"]
    static let chineseNumerals = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

    /// 机器记法，与测试脚本、Gemini 输出一致：`5p`、`3m`、`7s`，字牌直接写汉字。
    public var notation: String {
        isHonor ? Tile.honorNames[rank - 1] : "\(rank)\(suit.letter)"
    }

    /// 给人看的名字：`5饼`、`3万`、`东`。
    public var displayName: String {
        isHonor ? Tile.honorNames[rank - 1] : "\(rank)\(suit.chineseName)"
    }

    /// 牌面上的大字：万子写「五」，字牌写「中」，饼条不用。
    public var faceCharacter: String {
        switch suit {
        case .characters: Tile.chineseNumerals[rank - 1]
        case .honors: Tile.honorNames[rank - 1]
        default: "\(rank)"
        }
    }
}

extension Tile: CustomStringConvertible {
    public var description: String { notation }
}

extension Tile: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let tile = Tile(notation: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法识别的牌：\(text)")
        }
        self = tile
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(notation)
    }
}

// MARK: - 解析

extension Tile {
    /// 解析一张牌。接受 `5p` `5s` `5m` `5z`（字牌按东南西北中发白排 1–7），以及 `5饼` `5筒` `5条` `5索` `5万` `五万` `东` `發` 等写法。
    public init?(notation text: String) {
        let tiles = Tile.parseList(text)
        guard tiles.count == 1 else { return nil }
        self = tiles[0]
    }

    /// 解析一串牌，例如 `123m456p东东`、`1m 2m 3m`、`[3s, 4s, 5s]`、`五万 中`。无法识别的部分会被跳过。
    public static func parseList(_ text: String) -> [Tile] {
        var result: [Tile] = []
        var pendingRanks: [Int] = []

        func flush(_ suit: Suit) {
            for rank in pendingRanks {
                if let tile = Tile(suit: suit, rank: rank) { result.append(tile) }
            }
            pendingRanks.removeAll()
        }

        for ch in text {
            if let digit = ch.wholeNumberValue, (1...9).contains(digit) {
                pendingRanks.append(digit)
            } else if let index = chineseNumerals.firstIndex(of: String(ch)) {
                pendingRanks.append(index + 1)
            } else if let suit = suitSuffix(ch) {
                flush(suit)
            } else if let honor = honorRank(ch) {
                pendingRanks.removeAll()
                result.append(Tile(.honors, honor))
            } else {
                // 分隔符或其他字符：没有花色的数字作废
                if !pendingRanks.isEmpty && !ch.isWhitespace && ch != "," && ch != "，" {
                    pendingRanks.removeAll()
                }
            }
        }
        return result
    }

    private static func suitSuffix(_ ch: Character) -> Suit? {
        switch ch {
        case "m", "万", "萬": .characters
        case "s", "条", "條", "索": .bamboo
        case "p", "饼", "餅", "筒": .dots
        case "z": .honors
        default: nil
        }
    }

    private static func honorRank(_ ch: Character) -> Int? {
        switch ch {
        case "东", "東": 1
        case "南": 2
        case "西": 3
        case "北": 4
        case "中": 5
        case "发", "發": 6
        case "白": 7
        default: nil
        }
    }
}

extension Array where Element == Tile {
    /// 紧凑记法，例如 `123m456p东东`。
    public var compactNotation: String {
        var out = ""
        var run: [Int] = []
        var runSuit: Suit?
        func flush() {
            if let suit = runSuit, !run.isEmpty {
                out += run.map(String.init).joined() + String(suit.letter)
            }
            run.removeAll()
        }
        for tile in self {
            if tile.isHonor {
                flush(); runSuit = nil
                out += tile.notation
            } else {
                if runSuit != tile.suit { flush(); runSuit = tile.suit }
                run.append(tile.rank)
            }
        }
        flush()
        return out
    }

    /// 给人看的文字写法，同花色连写：`567饼 3万 东东`。
    public var displayText: String {
        var groups: [String] = []
        var run: [Int] = []
        var runSuit: Suit?
        func flush() {
            if let suit = runSuit, !run.isEmpty {
                groups.append(run.map(String.init).joined() + suit.chineseName)
            }
            run.removeAll()
        }
        for tile in self {
            if tile.isHonor {
                flush(); runSuit = nil
                groups.append(tile.displayName)
            } else {
                if runSuit != tile.suit { flush(); runSuit = tile.suit }
                run.append(tile.rank)
            }
        }
        flush()
        return groups.joined(separator: " ")
    }
}
