import Foundation

/// 照片拍不出来、要从牌局或用户确认里拿的川麻算番条件。
public struct WinContext: Hashable, Codable, Sendable {
    public var prevalentWind: Wind
    public var seatWind: Wind
    public var selfDrawn: Bool
    /// 杠上开花（自摸 +1 番）。
    public var gangShangHua: Bool
    /// 杠上炮（点炮 +1 番，并触发呼叫转移）。
    public var gangShangPao: Bool
    /// 抢杠胡（点炮 +1 番）。
    public var qiangGangHu: Bool
    /// 海底捞月（自摸）/ 海底炮（点炮）+1 番。
    public var lastTileOfWall: Bool
    /// 天胡（庄家起手胡）。
    public var tianHu: Bool
    /// 地胡（闲家第一巡胡）。
    public var diHu: Bool
    /// 家规：是否开启「门清 +1 番」。
    public var allowMenQing: Bool
    /// 家规：是否开启「中张（断幺九）+1 番」。
    public var allowZhongZhang: Bool
    /// 家规：是否为「自摸加番」（true 时自摸 +1 番；false 为成都主流「自摸加底」）。
    public var selfDrawnAddFan: Bool
    /// 点杠花时，点直杠的那个人（当家规为「点杠花算点炮」时由该玩家包付）。
    public var dianGangDiscarder: Int?

    // 兼容旧字段
    public var lastTileOfItsKind: Bool {
        get { false }
        set {}
    }
    public var kongInvolved: Bool {
        get { gangShangHua || gangShangPao || qiangGangHu }
        set {
            if newValue {
                if selfDrawn { gangShangHua = true } else { qiangGangHu = true }
            } else {
                gangShangHua = false
                gangShangPao = false
                qiangGangHu = false
            }
        }
    }
    public var flowerCount: Int

    public init(
        prevalentWind: Wind = .east,
        seatWind: Wind = .east,
        selfDrawn: Bool = false,
        gangShangHua: Bool = false,
        gangShangPao: Bool = false,
        qiangGangHu: Bool = false,
        lastTileOfWall: Bool = false,
        tianHu: Bool = false,
        diHu: Bool = false,
        allowMenQing: Bool = false,
        allowZhongZhang: Bool = false,
        selfDrawnAddFan: Bool = false,
        dianGangDiscarder: Int? = nil,
        kongInvolved: Bool = false,
        flowerCount: Int = 0
    ) {
        self.prevalentWind = prevalentWind
        self.seatWind = seatWind
        self.selfDrawn = selfDrawn
        self.gangShangHua = gangShangHua || (kongInvolved && selfDrawn)
        self.gangShangPao = gangShangPao
        self.qiangGangHu = qiangGangHu || (kongInvolved && !selfDrawn && !gangShangPao)
        self.lastTileOfWall = lastTileOfWall
        self.tianHu = tianHu
        self.diHu = diHu
        self.allowMenQing = allowMenQing
        self.allowZhongZhang = allowZhongZhang
        self.selfDrawnAddFan = selfDrawnAddFan
        self.dianGangDiscarder = dianGangDiscarder
        self.flowerCount = flowerCount
    }

    enum CodingKeys: String, CodingKey {
        case prevalentWind, seatWind, selfDrawn
        case gangShangHua, gangShangPao, qiangGangHu, lastTileOfWall
        case tianHu, diHu, allowMenQing, allowZhongZhang, selfDrawnAddFan, dianGangDiscarder
        case flowerCount
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case kongInvolved
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self)
        prevalentWind = try c.decodeIfPresent(Wind.self, forKey: .prevalentWind) ?? .east
        seatWind = try c.decodeIfPresent(Wind.self, forKey: .seatWind) ?? .east
        let selfDrawn = try c.decodeIfPresent(Bool.self, forKey: .selfDrawn) ?? false
        self.selfDrawn = selfDrawn
        let legacyKong = try legacy?.decodeIfPresent(Bool.self, forKey: .kongInvolved) ?? false
        gangShangHua = try c.decodeIfPresent(Bool.self, forKey: .gangShangHua) ?? (legacyKong && selfDrawn)
        gangShangPao = try c.decodeIfPresent(Bool.self, forKey: .gangShangPao) ?? false
        qiangGangHu = try c.decodeIfPresent(Bool.self, forKey: .qiangGangHu) ?? (legacyKong && !selfDrawn)
        lastTileOfWall = try c.decodeIfPresent(Bool.self, forKey: .lastTileOfWall) ?? false
        tianHu = try c.decodeIfPresent(Bool.self, forKey: .tianHu) ?? false
        diHu = try c.decodeIfPresent(Bool.self, forKey: .diHu) ?? false
        allowMenQing = try c.decodeIfPresent(Bool.self, forKey: .allowMenQing) ?? false
        allowZhongZhang = try c.decodeIfPresent(Bool.self, forKey: .allowZhongZhang) ?? false
        selfDrawnAddFan = try c.decodeIfPresent(Bool.self, forKey: .selfDrawnAddFan) ?? false
        dianGangDiscarder = try c.decodeIfPresent(Int.self, forKey: .dianGangDiscarder)
        flowerCount = try c.decodeIfPresent(Int.self, forKey: .flowerCount) ?? 0
    }
}

public struct ScoringResult: Hashable, Codable, Sendable {
    public let fans: [FanEntry]
    /// 整手牌中「根」（4 张相同的牌）的总数（含已计入龙七对/十八罗汉的根）。
    public let genCount: Int
    /// 兼容字段（川麻无花牌，恒为 0）。
    public let flowerFan: Int
    /// 兼容字段。
    public let fu: Int

    public init(fans: [FanEntry], genCount: Int = 0, flowerFan: Int = 0, fu: Int = 0) {
        self.fans = fans
        self.genCount = genCount
        self.flowerFan = flowerFan
        self.fu = fu
    }

    public var fanWithoutFlowers: Int {
        fans.reduce(0) { $0 + $1.points }
    }

    /// 总番数（平胡 0 番，对对胡 1 番，清一色 2 番……）。
    public var totalFan: Int {
        fanWithoutFlowers + flowerFan
    }

    /// 番型对应的基础倍数（$2^{\text{番数}}$，如 0 番 = 1 倍，1 番 = 2 倍，2 番 = 4 倍，3 番 = 8 倍）。
    public var baseMultiplier: Int {
        1 << min(max(0, totalFan), 20)
    }

    public var isYakuman: Bool {
        fans.contains { $0.fan.isLimitFan }
    }

    /// 是否满足起胡番数（四川麻将默认 0 番平胡即可起胡）。
    public func meetsMinimum(_ minimum: Int = 0) -> Bool {
        totalFan >= minimum
    }

    public func contains(_ fan: Fan) -> Bool {
        fans.contains { $0.fan == fan }
    }
}

public enum ScoringError: Error, Hashable, Sendable {
    case wrongTileCount
    case tileMoreThanFour
    /// 花猪（万、筒、条三门俱全，未缺一门不能胡）。
    case missingSuitRequired
    case notAWin
}

/// 四川麻将（血战到底 / 血流成河）算番与数「根」引擎。
public enum FanCalculator {
    public static func score(_ hand: Hand, context: WinContext = WinContext()) -> Result<ScoringResult, ScoringError> {
        guard hand.hasValidTileCount, hand.melds.allSatisfy(\.isValid) else { return .failure(.wrongTileCount) }
        guard hand.overusedTiles.isEmpty else { return .failure(.tileMoreThanFour) }
        guard !hand.isHuaZhu else { return .failure(.missingSuitRequired) }

        let candidates = evaluateAllCandidates(hand: hand, context: context)
        guard let best = candidates.max(by: { $0.totalFan < $1.totalFan }) else {
            return .failure(.notAWin)
        }
        return .success(best)
    }

    /// 判定这 14 张牌（含副露）在川麻规则下能不能胡（需缺一门，且满足 4 面子 + 1 对将 或 7 对子）。
    public static func isWinningShape(_ hand: Hand) -> Bool {
        guard hand.hasValidTileCount,
              hand.melds.allSatisfy(\.isValid),
              hand.overusedTiles.isEmpty,
              !hand.isHuaZhu else { return false }
        if hand.melds.isEmpty && isQiDuiShape(hand.concealed) {
            return true
        }
        return !standardDecompositions(concealed: hand.concealed, neededGroups: 4 - hand.melds.count).isEmpty
    }

    /// 13 张牌（含副露时立牌为 `13 - 3 * 副露数`）下叫听哪些牌（需满足缺一门，已满 4 张的牌不算）。
    public static func waitingTiles(melds: [Meld] = [], standing: [Tile]) -> [Tile] {
        guard melds.count * 3 + standing.count == 13, melds.allSatisfy(\.isValid) else { return [] }
        let existing = melds.flatMap(\.tiles) + standing
        guard !existing.contains(where: \.isHonor) else { return [] }
        let existingSuits = Set(existing.map(\.suit))
        // 三门俱全已经是花猪，不可能下叫
        guard existingSuits.count <= 2 else { return [] }

        let used = Dictionary(grouping: existing, by: { $0 }).mapValues(\.count)
        guard used.values.allSatisfy({ $0 <= 4 }) else { return [] }

        return Tile.all.filter { candidate in
            guard (used[candidate] ?? 0) < 4 else { return false }
            let hand = Hand(melds: melds, concealed: standing + [candidate], winningTile: candidate)
            return isWinningShape(hand)
        }
    }

    // MARK: - 候选评估

    private static func evaluateAllCandidates(hand: Hand, context: WinContext) -> [ScoringResult] {
        var results: [ScoringResult] = []
        let genCount = hand.genCount

        // 1. 七对 / 龙七对 / 清七对 / 清龙七对（门前清 14 张，全为对子或四张）
        if hand.melds.isEmpty && isQiDuiShape(hand.concealed) {
            results.append(scoreQiDui(hand: hand, genCount: genCount, context: context))
        }

        // 2. 标准形（4 面子 + 1 对将）
        let needed = 4 - hand.melds.count
        let decomps = standardDecompositions(concealed: hand.concealed, neededGroups: needed)
        for decomp in decomps {
            results.append(scoreStandard(hand: hand, decomp: decomp, genCount: genCount, context: context))
        }

        return results
    }

    /// 川麻七对形态：14 张立牌，每种牌出现 2 张或 4 张（含龙七对、双龙七对、三龙七对）。
    static func isQiDuiShape(_ tiles: [Tile]) -> Bool {
        guard tiles.count == 14, tiles.allSatisfy(\.isNumbered) else { return false }
        let counts = Dictionary(grouping: tiles, by: { $0 }).mapValues(\.count)
        return counts.values.allSatisfy { $0 == 2 || $0 == 4 }
    }

    private enum ConcealedGroup: Hashable {
        case chow(Tile)
        case pung(Tile)

        var isChow: Bool {
            if case .chow = self { return true }
            return false
        }

        var tiles: [Tile] {
            switch self {
            case .chow(let s):
                return [s, Tile(s.suit, s.rank + 1), Tile(s.suit, s.rank + 2)]
            case .pung(let t):
                return [t, t, t]
            }
        }
    }

    private struct Decomposition: Hashable {
        var groups: [ConcealedGroup]
        var pair: Tile
    }

    private static func standardDecompositions(concealed: [Tile], neededGroups: Int) -> [Decomposition] {
        guard neededGroups >= 0,
              concealed.count == neededGroups * 3 + 2,
              concealed.allSatisfy(\.isNumbered) else { return [] }
        var counts = [Int](repeating: 0, count: 27)
        for t in concealed { counts[tileIndex(t)] += 1 }

        var unique = Set<Decomposition>()
        for pairIdx in 0..<27 where counts[pairIdx] >= 2 {
            counts[pairIdx] -= 2
            let pairTile = tileFromIndex(pairIdx)
            var current: [ConcealedGroup] = []
            func search(_ remaining: Int) {
                if remaining == 0 {
                    let sortedGroups = current.sorted { lhs, rhs in
                        switch (lhs, rhs) {
                        case (.chow(let a), .chow(let b)): return a < b
                        case (.pung(let a), .pung(let b)): return a < b
                        case (.chow, .pung): return true
                        case (.pung, .chow): return false
                        }
                    }
                    unique.insert(Decomposition(groups: sortedGroups, pair: pairTile))
                    return
                }
                guard let first = counts.firstIndex(where: { $0 > 0 }) else { return }
                let tile = tileFromIndex(first)

                if counts[first] >= 3 {
                    counts[first] -= 3
                    current.append(.pung(tile))
                    search(remaining - 1)
                    current.removeLast()
                    counts[first] += 3
                }

                if (first % 9) <= 6 && counts[first + 1] > 0 && counts[first + 2] > 0 {
                    counts[first] -= 1
                    counts[first + 1] -= 1
                    counts[first + 2] -= 1
                    current.append(.chow(tile))
                    search(remaining - 1)
                    current.removeLast()
                    counts[first] += 1
                    counts[first + 1] += 1
                    counts[first + 2] += 1
                }
            }
            search(neededGroups)
            counts[pairIdx] += 2
        }
        return Array(unique)
    }

    private static func tileIndex(_ tile: Tile) -> Int {
        (tile.suit.rawValue - 1) * 9 + (tile.rank - 1)
    }

    private static func tileFromIndex(_ index: Int) -> Tile {
        let suit = Suit(rawValue: (index / 9) + 1)!
        return Tile(suit, (index % 9) + 1)
    }

    // MARK: - 七对 / 龙七对计分

    private static func scoreQiDui(hand: Hand, genCount: Int, context: WinContext) -> ScoringResult {
        var entries: [FanEntry] = []
        let isQing = hand.suits.count == 1

        if genCount >= 1 {
            // 龙七对 / 清龙七对：自带第 1 根，不再重复算第 1 根；双龙/三龙七对额外加 (genCount - 1) 根
            entries.append(FanEntry(fan: isQing ? .qingLongQiDui : .longQiDui))
            let extraGen = genCount - 1
            if extraGen > 0 {
                entries.append(FanEntry(fan: .gen, count: extraGen))
            }
        } else {
            entries.append(FanEntry(fan: isQing ? .qingQiDui : .qiDui))
        }

        appendAdditiveFans(to: &entries, hand: hand, isQiDui: true, context: context)
        return ScoringResult(fans: sortEntries(entries), genCount: genCount)
    }

    // MARK: - 标准形（4 面子 + 1 对将）计分

    private static func scoreStandard(
        hand: Hand,
        decomp: Decomposition,
        genCount: Int,
        context: WinContext
    ) -> ScoringResult {
        let allTiles = hand.allTiles
        let isQing = hand.suits.count == 1
        let isAllTriplets = hand.melds.allSatisfy { $0.kind == .pung || $0.kind == .kong }
            && decomp.groups.allSatisfy { !$0.isChow }
        let isJinGouDiao = isAllTriplets && hand.melds.count == 4 && hand.concealed.count == 2
        let isShiBaLuoHan = isJinGouDiao && hand.kongCount == 4
        let isJiang = isAllTriplets && allTiles.allSatisfy(\.isJiang)

        let allGroupTiles: [[Tile]] = hand.melds.map(\.tiles) + decomp.groups.map(\.tiles)
        let isDaiYao = allGroupTiles.allSatisfy { $0.contains(where: \.isTerminal) } && decomp.pair.isTerminal

        var entries: [FanEntry] = []

        if isShiBaLuoHan {
            entries.append(FanEntry(fan: .shiBaLuoHan))
            if isQing { entries.append(FanEntry(fan: .qingYiSe)) }
            if isJiang { entries.append(FanEntry(fan: .jiangDui)) }
        } else if isJinGouDiao {
            if isQing && isJiang {
                entries.append(FanEntry(fan: .qingJinGouDiao))
                entries.append(FanEntry(fan: .jiangDui))
            } else if isQing {
                entries.append(FanEntry(fan: .qingJinGouDiao))
            } else if isJiang {
                entries.append(FanEntry(fan: .jiangJinGou))
            } else {
                entries.append(FanEntry(fan: .jinGouDiao))
            }
        } else if isAllTriplets {
            if isQing && isJiang {
                entries.append(FanEntry(fan: .qingYiSe))
                entries.append(FanEntry(fan: .jiangDui))
            } else if isJiang {
                entries.append(FanEntry(fan: .jiangDui))
            } else if isQing {
                entries.append(FanEntry(fan: .qingDui))
            } else if isDaiYao {
                entries.append(FanEntry(fan: .daiYaoJiu))
                entries.append(FanEntry(fan: .duiDuiHu))
            } else {
                entries.append(FanEntry(fan: .duiDuiHu))
            }
        } else {
            if isQing && isDaiYao {
                entries.append(FanEntry(fan: .qingDaiYao))
            } else if isDaiYao {
                entries.append(FanEntry(fan: .daiYaoJiu))
            } else if isQing {
                entries.append(FanEntry(fan: .qingYiSe))
            } else {
                entries.append(FanEntry(fan: .pingHu))
            }
        }

        // 根（十八罗汉已包含 4 杠，其余牌型每有 4 张同牌 +1 番）
        if !isShiBaLuoHan && genCount > 0 {
            entries.append(FanEntry(fan: .gen, count: genCount))
        }

        appendAdditiveFans(to: &entries, hand: hand, isQiDui: false, context: context)
        return ScoringResult(fans: sortEntries(entries), genCount: genCount)
    }

    private static func appendAdditiveFans(to entries: inout [FanEntry], hand: Hand, isQiDui: Bool, context: WinContext) {
        if context.tianHu {
            entries.append(FanEntry(fan: .tianHu))
        } else if context.diHu {
            entries.append(FanEntry(fan: .diHu))
        }

        if context.gangShangHua {
            entries.append(FanEntry(fan: .gangShangHua))
        } else if context.gangShangPao {
            entries.append(FanEntry(fan: .gangShangPao))
        } else if context.qiangGangHu {
            entries.append(FanEntry(fan: .qiangGangHu))
        }

        if context.lastTileOfWall {
            entries.append(FanEntry(fan: context.selfDrawn ? .haiDiLaoYue : .haiDiPao))
        }

        // 可选家规：门清（无碰、无明杠；七对本身已要求门前清，标准形或家规开启时计门清）
        if context.allowMenQing && hand.isConcealedHand && !isQiDui {
            entries.append(FanEntry(fan: .menQing))
        }

        // 可选家规：中张（断幺九，全 2–8）
        if context.allowZhongZhang && hand.allTiles.allSatisfy(\.isSimple) {
            entries.append(FanEntry(fan: .zhongZhang))
        }

        // 可选家规：自摸加番
        if context.selfDrawn && context.selfDrawnAddFan {
            entries.append(FanEntry(fan: .ziMoJiaFan))
        }
    }

    private static func sortEntries(_ entries: [FanEntry]) -> [FanEntry] {
        // 如果已经有高番主牌型或其他加番，平胡（0 番）保留在最前或当总番 > 0 且存在 >0 番主牌型时不冗余展示；
        // 但平胡 + 根 / 平胡 + 杠上花 时保留「平胡（0番）」+「根（1番）」非常直观。
        entries.sorted { lhs, rhs in
            if lhs.fan == .pingHu && rhs.fan != .pingHu { return true }
            if rhs.fan == .pingHu && lhs.fan != .pingHu { return false }
            return (lhs.points, -lhs.fan.rawValue) > (rhs.points, -rhs.fan.rawValue)
        }
    }
}
