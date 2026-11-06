import Foundation

/// 一组碰、杠（四川麻将不能吃牌；保留 `.chow` 仅供协议解码兼容）。暗杠也放在这里（它在照片里摆在旁边，并且决定张数）。
public struct Meld: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case chow   // 吃（川麻不可吃，仅做解码兼容）
        case pung   // 碰
        case kong   // 杠（直杠/巴杠/暗杠）
    }

    public var kind: Kind
    /// 顺子写最小的那张；刻子和杠写那张牌。
    public var tile: Tile
    /// 只对杠有意义：true 为暗杠（下雨），false 为明杠/巴杠（刮风）。
    public var isConcealed: Bool

    /// 四川麻将副露只能是万筒条序数牌的碰或杠（不能吃牌、不能有字牌）。
    public var isValid: Bool {
        guard tile.isNumbered else { return false }
        switch kind {
        case .chow:
            return false
        case .pung, .kong:
            return true
        }
    }

    public init?(kind: Kind, tile: Tile, isConcealed: Bool = false) {
        if kind == .chow {
            guard tile.isNumbered, tile.rank <= 7 else { return nil }
        }
        self.kind = kind
        self.tile = tile
        self.isConcealed = kind == .kong ? isConcealed : false
    }

    public static func chow(_ lowest: Tile) -> Meld? { Meld(kind: .chow, tile: lowest) }
    public static func pung(_ tile: Tile) -> Meld { Meld(kind: .pung, tile: tile)! }
    public static func kong(_ tile: Tile, concealed: Bool) -> Meld { Meld(kind: .kong, tile: tile, isConcealed: concealed)! }

    public var tiles: [Tile] {
        switch kind {
        case .chow:
            [tile, Tile(tile.suit, tile.rank + 1), Tile(tile.suit, tile.rank + 2)]
        case .pung:
            [tile, tile, tile]
        case .kong:
            [tile, tile, tile, tile]
        }
    }

    public var kindName: String {
        switch kind {
        case .chow: "吃"
        case .pung: "碰"
        case .kong: isConcealed ? "暗杠" : "明杠"
        }
    }

    /// 例如「碰 5筒」「暗杠 9万」。
    public var displayText: String {
        switch kind {
        case .chow: "\(kindName) \(tiles.displayText)"
        default: "\(kindName) \(tile.displayName)"
        }
    }

    /// 由 3 或 4 张牌推出一组川麻副露（仅支持碰、杠；若模型误报顺子则拆回手牌处理）。
    public static func from(tiles: [Tile], concealedKong: Bool = false) -> Meld? {
        let sorted = tiles.sorted()
        guard sorted.allSatisfy(\.isNumbered) else { return nil }
        switch sorted.count {
        case 4 where Set(sorted).count == 1:
            return .kong(sorted[0], concealed: concealedKong)
        case 3 where Set(sorted).count == 1:
            return .pung(sorted[0])
        default:
            return nil
        }
    }
}

/// 座位方位（东南西北）。
public enum Wind: Int, Codable, CaseIterable, Sendable {
    case east = 0, south, west, north

    public var name: String { ["东", "南", "西", "北"][rawValue] }
    public var tile: Tile { Tile(.honors, rawValue + 1) }

    /// 逆时针下一个（东 → 南 → 西 → 北 → 东）。
    public var next: Wind { Wind(rawValue: (rawValue + 1) % 4)! }
}

/// 一手牌：副露（碰/杠） + 立牌（胡牌时含胡的那张共 14 张；查叫时立牌为 13 张）。
public struct Hand: Hashable, Codable, Sendable {
    public var melds: [Meld]
    /// 立牌，包括胡的那张。照片里从左到右的顺序。
    public var concealed: [Tile]
    public var winningTile: Tile

    public init(melds: [Meld] = [], concealed: [Tile], winningTile: Tile? = nil) {
        self.melds = melds
        self.concealed = concealed
        self.winningTile = winningTile ?? concealed.last ?? Tile(.characters, 1)
    }

    /// 所有牌（杠算 4 张）。
    public var allTiles: [Tile] { melds.flatMap(\.tiles) + concealed }

    public var kongCount: Int { melds.filter { $0.kind == .kong }.count }

    /// 整手牌中出现的序数牌花色集合（万、条、筒）。
    public var suits: Set<Suit> {
        Set(allTiles.filter(\.isNumbered).map(\.suit))
    }

    /// 是否「花猪」（万、条、筒三门花色同时存在，或含非法字牌）。
    public var isHuaZhu: Bool {
        suits.count >= 3 || allTiles.contains(where: \.isHonor)
    }

    /// 是否满足川麻「缺一门」（全为序数牌且至多 2 种花色）。
    public var isMissingOneSuit: Bool {
        !allTiles.isEmpty && !allTiles.contains(where: \.isHonor) && suits.count <= 2
    }

    /// 整手牌（含已碰、已杠、手牌）中「根」（4 张相同的牌）的总数。
    public var genCount: Int {
        Dictionary(grouping: allTiles, by: { $0 }).values.filter { $0.count == 4 }.count
    }

    /// 胡牌立牌张数是否正确：3 × 副露组数 + 立牌 = 14。
    public var hasValidTileCount: Bool { concealed.count + 3 * melds.count == 14 }

    /// 查大叫立牌张数是否正确：3 × 副露组数 + 立牌 = 13。
    public var hasValidTenpaiTileCount: Bool { concealed.count + 3 * melds.count == 13 }

    /// 超过 4 张的牌。
    public var overusedTiles: [Tile] {
        Dictionary(grouping: allTiles, by: { $0 }).filter { $0.value.count > 4 }.keys.sorted()
    }

    /// 门前清（无碰、无明杠；暗杠不算破门清）。
    public var isConcealedHand: Bool { melds.allSatisfy { $0.kind == .kong && $0.isConcealed } }

    /// 是否为「金钩钓」形态（4 组碰/杠亮出，手牌只剩单吊 1 对将牌）。
    public var isJinGouDiao: Bool {
        melds.count == 4 && melds.allSatisfy(\.isValid) && concealed.count == 2 && concealed[0] == concealed[1]
    }
}
