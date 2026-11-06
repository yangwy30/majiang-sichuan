import Foundation

/// 照片拍不出来、要从牌局或用户确认里拿的算番条件。
public struct WinContext: Hashable, Codable, Sendable {
    public var prevalentWind: Wind
    public var seatWind: Wind
    public var selfDrawn: Bool
    /// 立直（门前清听牌宣布立直）。
    public var riichi: Bool
    /// 双立直（第一巡无人副露时立直）。
    public var doubleRiichi: Bool
    /// 一发（立直后一巡内和牌，中间无人吃碰杠）。
    public var ippatsu: Bool
    /// 海底摸月（自摸）/ 河底捞鱼（点炮）。
    public var lastTileOfWall: Bool
    /// 兼容旧字段。
    public var lastTileOfItsKind: Bool
    /// 岭上开花（自摸）/ 抢杠（点炮）。
    public var kongInvolved: Bool
    /// 宝牌总数（含表宝牌、赤宝牌、里宝牌）。每张 +1 翻，不算进起和役。
    public var flowerCount: Int

    public init(
        prevalentWind: Wind = .east,
        seatWind: Wind = .east,
        selfDrawn: Bool = false,
        riichi: Bool = false,
        doubleRiichi: Bool = false,
        ippatsu: Bool = false,
        lastTileOfWall: Bool = false,
        lastTileOfItsKind: Bool = false,
        kongInvolved: Bool = false,
        flowerCount: Int = 0
    ) {
        self.prevalentWind = prevalentWind
        self.seatWind = seatWind
        self.selfDrawn = selfDrawn
        self.riichi = riichi
        self.doubleRiichi = doubleRiichi
        self.ippatsu = ippatsu
        self.lastTileOfWall = lastTileOfWall
        self.lastTileOfItsKind = lastTileOfItsKind
        self.kongInvolved = kongInvolved
        self.flowerCount = flowerCount
    }

    enum CodingKeys: String, CodingKey {
        case prevalentWind, seatWind, selfDrawn, riichi, doubleRiichi, ippatsu
        case lastTileOfWall, lastTileOfItsKind, kongInvolved, flowerCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        prevalentWind = try c.decodeIfPresent(Wind.self, forKey: .prevalentWind) ?? .east
        seatWind = try c.decodeIfPresent(Wind.self, forKey: .seatWind) ?? .east
        selfDrawn = try c.decodeIfPresent(Bool.self, forKey: .selfDrawn) ?? false
        riichi = try c.decodeIfPresent(Bool.self, forKey: .riichi) ?? false
        doubleRiichi = try c.decodeIfPresent(Bool.self, forKey: .doubleRiichi) ?? false
        ippatsu = try c.decodeIfPresent(Bool.self, forKey: .ippatsu) ?? false
        lastTileOfWall = try c.decodeIfPresent(Bool.self, forKey: .lastTileOfWall) ?? false
        lastTileOfItsKind = try c.decodeIfPresent(Bool.self, forKey: .lastTileOfItsKind) ?? false
        kongInvolved = try c.decodeIfPresent(Bool.self, forKey: .kongInvolved) ?? false
        flowerCount = try c.decodeIfPresent(Int.self, forKey: .flowerCount) ?? 0
    }
}

public struct ScoringResult: Hashable, Codable, Sendable {
    public let fans: [FanEntry]
    /// 宝牌翻数（不算进起和役；役满时不额外加宝牌）。
    public let flowerFan: Int
    /// 符数（七对子固定 25 符，平和自摸 20 符，其余按 10 符进位，最少 30 符）。
    public let fu: Int

    public init(fans: [FanEntry], flowerFan: Int = 0, fu: Int = 30) {
        self.fans = fans
        self.flowerFan = flowerFan
        self.fu = fu
    }

    /// 不含宝牌的役种翻数。立直麻将要求至少 1 翻役才能和。
    public var fanWithoutFlowers: Int {
        fans.reduce(0) { $0 + $1.points }
    }

    /// 含宝牌的总翻数。
    public var totalFan: Int {
        fanWithoutFlowers + flowerFan
    }

    public var isYakuman: Bool {
        fans.contains { $0.fan.isYakuman }
    }

    /// 够不够起和翻数（立直麻将默认 1 翻起和，宝牌不计入）。
    public func meetsMinimum(_ minimum: Int = 1) -> Bool {
        fanWithoutFlowers >= minimum
    }

    public func contains(_ fan: Fan) -> Bool {
        fans.contains { $0.fan == fan }
    }
}

public enum ScoringError: Error, Hashable, Sendable {
    case wrongTileCount
    case tileMoreThanFour
    case notAWin
}

/// 日本立直麻将算番算符引擎（纯 Swift 实现，遵循高点法）。
public enum FanCalculator {
    public static func score(_ hand: Hand, context: WinContext = WinContext()) -> Result<ScoringResult, ScoringError> {
        guard hand.hasValidTileCount else { return .failure(.wrongTileCount) }
        guard hand.overusedTiles.isEmpty else { return .failure(.tileMoreThanFour) }

        let candidates = evaluateAllCandidates(hand: hand, context: context)
        guard let best = candidates.max(by: isBetterCandidate) else {
            return .failure(.notAWin)
        }
        return .success(best)
    }

    /// 只看牌型能不能和（4 面子 + 1 雀头、七对子、国士无双），不管役种够不够 1 翻。
    public static func isWinningShape(_ hand: Hand) -> Bool {
        guard hand.hasValidTileCount, hand.overusedTiles.isEmpty else { return false }
        if hand.melds.isEmpty {
            if isKokushiShape(hand.concealed) || isChiitoitsuShape(hand.concealed) {
                return true
            }
        }
        return !standardDecompositions(concealed: hand.concealed, neededGroups: 4 - hand.melds.count).isEmpty
    }

    /// 13 张牌（含副露时立牌为 `13 - 3 * 副露数`）听哪些牌。已满 4 张的牌不算。
    public static func waitingTiles(melds: [Meld] = [], standing: [Tile]) -> [Tile] {
        guard melds.count * 3 + standing.count == 13, melds.allSatisfy(\.isValid) else { return [] }
        let used = Dictionary(grouping: melds.flatMap(\.tiles) + standing, by: { $0 }).mapValues(\.count)
        guard used.values.allSatisfy({ $0 <= 4 }) else { return [] }

        return Tile.all.filter { candidate in
            guard (used[candidate] ?? 0) < 4 else { return false }
            let hand = Hand(melds: melds, concealed: standing + [candidate], winningTile: candidate)
            return isWinningShape(hand)
        }
    }

    // MARK: - 高点法候选评估

    private static func isBetterCandidate(_ a: ScoringResult, _ b: ScoringResult) -> Bool {
        // 先确保有役的排在无役前面
        let aValid = a.fanWithoutFlowers > 0
        let bValid = b.fanWithoutFlowers > 0
        if aValid != bValid { return !aValid && bValid }

        let aBase = Payment.basePoints(han: a.totalFan, fu: a.fu)
        let bBase = Payment.basePoints(han: b.totalFan, fu: b.fu)
        if aBase != bBase { return aBase < bBase }
        if a.totalFan != b.totalFan { return a.totalFan < b.totalFan }
        return a.fu < b.fu
    }

    private static func evaluateAllCandidates(hand: Hand, context: WinContext) -> [ScoringResult] {
        var results: [ScoringResult] = []
        let isMenzen = hand.melds.allSatisfy { $0.kind == .kong && $0.isConcealed }

        // 1. 国士无双
        if hand.melds.isEmpty && isKokushiShape(hand.concealed) {
            let fans = [FanEntry(fan: .kokushi, count: 1)]
            results.append(ScoringResult(fans: fans, flowerFan: 0, fu: 30))
        }

        // 2. 七对子（7 个不同的对子，固定 25 符）
        if hand.melds.isEmpty && isChiitoitsuShape(hand.concealed) {
            results.append(scoreChiitoitsu(hand: hand, context: context))
        }

        // 3. 标准形（4 面子 + 1 雀头）
        let needed = 4 - hand.melds.count
        let decomps = standardDecompositions(concealed: hand.concealed, neededGroups: needed)
        let winTile = hand.winningTile
        for decomp in decomps {
            var targets = Set<WaitTarget>()
            if decomp.pair == winTile {
                targets.insert(.tanki)
            }
            for (idx, group) in decomp.groups.enumerated() {
                switch group {
                case .pung(let tile) where tile == winTile:
                    targets.insert(.group(index: idx, wait: .shanpon))
                case .chow(let start) where start.suit == winTile.suit && (start.rank...(start.rank + 2)).contains(winTile.rank):
                    let r = start.rank
                    let w = winTile.rank
                    let wait: WaitKind
                    if w == r + 1 {
                        wait = .kanchan
                    } else if (r == 1 && w == 3) || (r == 7 && w == 7) {
                        wait = .penchan
                    } else {
                        wait = .ryanmen
                    }
                    targets.insert(.group(index: idx, wait: wait))
                default:
                    break
                }
            }
            if targets.isEmpty {
                targets.insert(.tanki)
            }
            for target in targets {
                results.append(scoreStandard(hand: hand, decomp: decomp, target: target, isMenzen: isMenzen, context: context))
            }
        }

        return results
    }

    // MARK: - 牌型拆解

    private enum ConcealedGroup: Hashable {
        case chow(Tile)
        case pung(Tile)
    }

    private struct Decomposition: Hashable {
        var groups: [ConcealedGroup]
        var pair: Tile
    }

    private enum WaitKind: Hashable {
        case ryanmen
        case shanpon
        case kanchan
        case penchan
        case tanki

        var fu: Int {
            switch self {
            case .ryanmen, .shanpon: return 0
            case .kanchan, .penchan, .tanki: return 2
            }
        }
    }

    private enum WaitTarget: Hashable {
        case tanki
        case group(index: Int, wait: WaitKind)

        var waitKind: WaitKind {
            switch self {
            case .tanki: return .tanki
            case .group(_, let wait): return wait
            }
        }
    }

    private static func isKokushiShape(_ tiles: [Tile]) -> Bool {
        guard tiles.count == 14 else { return false }
        let counts = Dictionary(grouping: tiles, by: { $0 }).mapValues(\.count)
        guard counts.count == 13 else { return false }
        return counts.keys.allSatisfy(\.isTerminalOrHonor) && counts.values.contains(2)
    }

    private static func isChiitoitsuShape(_ tiles: [Tile]) -> Bool {
        guard tiles.count == 14 else { return false }
        let counts = Dictionary(grouping: tiles, by: { $0 }).mapValues(\.count)
        return counts.count == 7 && counts.values.allSatisfy { $0 == 2 }
    }

    private static func standardDecompositions(concealed: [Tile], neededGroups: Int) -> [Decomposition] {
        guard neededGroups >= 0, concealed.count == neededGroups * 3 + 2 else { return [] }
        var counts = [Int](repeating: 0, count: 34)
        for t in concealed { counts[tileIndex(t)] += 1 }

        var unique = Set<Decomposition>()
        for pairIdx in 0..<34 where counts[pairIdx] >= 2 {
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

                if first < 27 && (first % 9) <= 6 && counts[first + 1] > 0 && counts[first + 2] > 0 {
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

    // MARK: - 七对子计分

    private static func scoreChiitoitsu(hand: Hand, context: WinContext) -> ScoringResult {
        let allTiles = hand.allTiles
        // 字一色（大七星）
        if allTiles.allSatisfy(\.isHonor) {
            return ScoringResult(fans: [FanEntry(fan: .tsuuiisou)], flowerFan: 0, fu: 25)
        }

        var entries: [FanEntry] = []
        appendSituationalYaku(to: &entries, isMenzen: true, context: context)
        entries.append(FanEntry(fan: .chiitoitsu))
        appendAllTileYaku(to: &entries, allTiles: allTiles, isMenzen: true, isStandard: false)

        let sorted = entries.sorted { ($0.points, -$0.fan.rawValue) > ($1.points, -$1.fan.rawValue) }
        let dora = max(0, context.flowerCount)
        return ScoringResult(fans: sorted, flowerFan: dora, fu: 25)
    }

    // MARK: - 标准形计分（4 面子 + 1 雀头）

    private struct ResolvedGroup {
        enum Kind {
            case chow(Tile)
            case triplet(Tile, isConcealed: Bool, isKong: Bool)
        }
        var kind: Kind

        var tiles: [Tile] {
            switch kind {
            case .chow(let s):
                return [s, Tile(s.suit, s.rank + 1), Tile(s.suit, s.rank + 2)]
            case .triplet(let t, _, let isKong):
                return Array(repeating: t, count: isKong ? 4 : 3)
            }
        }

        var isChow: Bool {
            if case .chow = kind { return true }
            return false
        }

        var tripletTile: Tile? {
            if case .triplet(let t, _, _) = kind { return t }
            return nil
        }

        var isConcealedTriplet: Bool {
            if case .triplet(_, let isConcealed, _) = kind { return isConcealed }
            return false
        }

        var isKong: Bool {
            if case .triplet(_, _, let isKong) = kind { return isKong }
            return false
        }

        var fu: Int {
            switch kind {
            case .chow:
                return 0
            case .triplet(let tile, let isConcealed, let isKong):
                let yaochu = tile.isTerminalOrHonor
                switch (isKong, isConcealed) {
                case (false, false): return yaochu ? 4 : 2
                case (false, true):  return yaochu ? 8 : 4
                case (true, false):  return yaochu ? 16 : 8
                case (true, true):   return yaochu ? 32 : 16
                }
            }
        }
    }

    private static func scoreStandard(
        hand: Hand,
        decomp: Decomposition,
        target: WaitTarget,
        isMenzen: Bool,
        context: WinContext
    ) -> ScoringResult {
        var groups: [ResolvedGroup] = []
        for meld in hand.melds {
            switch meld.kind {
            case .chow:
                groups.append(ResolvedGroup(kind: .chow(meld.tiles[0])))
            case .pung:
                groups.append(ResolvedGroup(kind: .triplet(meld.tiles[0], isConcealed: false, isKong: false)))
            case .kong:
                groups.append(ResolvedGroup(kind: .triplet(meld.tiles[0], isConcealed: meld.isConcealed, isKong: true)))
            }
        }
        for (idx, g) in decomp.groups.enumerated() {
            switch g {
            case .chow(let s):
                groups.append(ResolvedGroup(kind: .chow(s)))
            case .pung(let t):
                let completedByRon: Bool
                if case .group(let targetIdx, _) = target, targetIdx == idx, !context.selfDrawn {
                    completedByRon = true
                } else {
                    completedByRon = false
                }
                groups.append(ResolvedGroup(kind: .triplet(t, isConcealed: !completedByRon, isKong: false)))
            }
        }

        let pair = decomp.pair
        let wait = target.waitKind
        let allTiles = hand.allTiles

        // 平和判定：门前清（且无暗杠）、4 组顺子、雀头非役牌、两面听
        let isYakuhaiPair = pair == context.seatWind.tile
            || pair == context.prevalentWind.tile
            || (pair.suit == .honors && pair.rank >= 5)
        let isPinfu = hand.melds.isEmpty
            && groups.allSatisfy(\.isChow)
            && !isYakuhaiPair
            && wait == .ryanmen

        // 符数计算
        let fu: Int
        if isPinfu {
            fu = context.selfDrawn ? 20 : 30
        } else {
            var rawFu = 20
            if isMenzen && !context.selfDrawn {
                rawFu += 10
            } else if context.selfDrawn {
                rawFu += 2
            }
            if pair.suit == .honors && pair.rank >= 5 { rawFu += 2 }
            if pair == context.seatWind.tile { rawFu += 2 }
            if pair == context.prevalentWind.tile { rawFu += 2 }
            rawFu += wait.fu
            for g in groups { rawFu += g.fu }
            let rounded = ((rawFu + 9) / 10) * 10
            fu = max(30, rounded)
        }

        // 先检查役满
        let yakuman = evaluateStandardYakuman(hand: hand, groups: groups, pair: pair, isMenzen: isMenzen)
        if !yakuman.isEmpty {
            return ScoringResult(fans: yakuman, flowerFan: 0, fu: fu)
        }

        // 普通役种
        var entries: [FanEntry] = []
        appendSituationalYaku(to: &entries, isMenzen: isMenzen, context: context)
        if isPinfu {
            entries.append(FanEntry(fan: .pinfu))
        }

        let chows = groups.compactMap { g -> Tile? in
            if case .chow(let s) = g.kind { return s }
            return nil
        }
        let triplets = groups.compactMap(\.tripletTile)
        let ankouCount = groups.filter(\.isConcealedTriplet).count
        let kongCount = groups.filter(\.isKong).count

        // 一杯口 / 二杯口（门前限定）
        if isMenzen {
            let chowCounts = Dictionary(grouping: chows, by: { $0 }).mapValues(\.count)
            let pairCount = chowCounts.values.reduce(0) { $0 + ($1 / 2) }
            if pairCount == 2 {
                entries.append(FanEntry(fan: .ryanpeiko))
            } else if pairCount == 1 {
                entries.append(FanEntry(fan: .iipeiko))
            }
        }

        // 役牌（自风、场风、白、发、中）
        for t in triplets {
            if t == context.seatWind.tile { entries.append(FanEntry(fan: .seatWind)) }
            if t == context.prevalentWind.tile { entries.append(FanEntry(fan: .prevalentWind)) }
            if t == Tile(.honors, 7) { entries.append(FanEntry(fan: .whiteDragon)) }
            if t == Tile(.honors, 6) { entries.append(FanEntry(fan: .greenDragon)) }
            if t == Tile(.honors, 5) { entries.append(FanEntry(fan: .redDragon)) }
        }

        // 三色同顺
        let chowSet = Set(chows)
        if (1...7).contains(where: { r in
            chowSet.contains(Tile(.characters, r))
                && chowSet.contains(Tile(.dots, r))
                && chowSet.contains(Tile(.bamboo, r))
        }) {
            entries.append(makeEntry(.sanshokuDoujun, isMenzen: isMenzen))
        }

        // 一气通贯
        if [Suit.characters, .dots, .bamboo].contains(where: { s in
            chowSet.contains(Tile(s, 1)) && chowSet.contains(Tile(s, 4)) && chowSet.contains(Tile(s, 7))
        }) {
            entries.append(makeEntry(.ittsuu, isMenzen: isMenzen))
        }

        // 对对和 / 三暗刻 / 三杠子 / 三色同刻 / 小三元
        if triplets.count == 4 {
            entries.append(FanEntry(fan: .toitoi))
        }
        if ankouCount == 3 {
            entries.append(FanEntry(fan: .sanankou))
        }
        if kongCount == 3 {
            entries.append(FanEntry(fan: .sankantsu))
        }
        let tripletSet = Set(triplets)
        if (1...9).contains(where: { r in
            tripletSet.contains(Tile(.characters, r))
                && tripletSet.contains(Tile(.dots, r))
                && tripletSet.contains(Tile(.bamboo, r))
        }) {
            entries.append(FanEntry(fan: .sanshokuDoukou))
        }
        let dragons: [Tile] = [Tile(.honors, 5), Tile(.honors, 6), Tile(.honors, 7)]
        if dragons.filter({ tripletSet.contains($0) }).count == 2 && dragons.contains(pair) {
            entries.append(FanEntry(fan: .shousangen))
        }

        // 整手牌相关役（断幺九、混老头、混一色、清一色）
        appendAllTileYaku(to: &entries, allTiles: allTiles, isMenzen: isMenzen, isStandard: true)

        // 纯全带幺九 / 混全带幺九（必须至少有一组顺子，否则是清老头或混老头）
        if !chows.isEmpty {
            let allGroupsHaveTerminal = groups.allSatisfy { $0.tiles.contains(where: \.isTerminal) } && pair.isTerminal
            let allGroupsHaveYaochu = groups.allSatisfy { $0.tiles.contains(where: \.isTerminalOrHonor) } && pair.isTerminalOrHonor
            if allGroupsHaveTerminal {
                entries.append(makeEntry(.junchan, isMenzen: isMenzen))
            } else if allGroupsHaveYaochu {
                entries.append(makeEntry(.chanta, isMenzen: isMenzen))
            }
        }

        let sorted = entries.sorted { ($0.points, -$0.fan.rawValue) > ($1.points, -$1.fan.rawValue) }
        let dora = max(0, context.flowerCount)
        return ScoringResult(fans: sorted, flowerFan: dora, fu: fu)
    }

    private static func evaluateStandardYakuman(
        hand: Hand,
        groups: [ResolvedGroup],
        pair: Tile,
        isMenzen: Bool
    ) -> [FanEntry] {
        var yakuman: [FanEntry] = []
        let allTiles = hand.allTiles
        let triplets = Set(groups.compactMap(\.tripletTile))
        let ankouCount = groups.filter(\.isConcealedTriplet).count
        let kongCount = groups.filter(\.isKong).count

        if ankouCount == 4 {
            yakuman.append(FanEntry(fan: .suuankou))
        }
        let dragons: [Tile] = [Tile(.honors, 5), Tile(.honors, 6), Tile(.honors, 7)]
        if dragons.allSatisfy({ triplets.contains($0) }) {
            yakuman.append(FanEntry(fan: .daisangen))
        }
        let winds: [Tile] = [Tile(.honors, 1), Tile(.honors, 2), Tile(.honors, 3), Tile(.honors, 4)]
        let windTriplets = winds.filter { triplets.contains($0) }.count
        if windTriplets == 4 {
            yakuman.append(FanEntry(fan: .daisuushii))
        } else if windTriplets == 3 && winds.contains(pair) {
            yakuman.append(FanEntry(fan: .shousuushii))
        }
        if allTiles.allSatisfy(\.isHonor) {
            yakuman.append(FanEntry(fan: .tsuuiisou))
        }
        if allTiles.allSatisfy(\.isTerminal) {
            yakuman.append(FanEntry(fan: .chinroutou))
        }
        let greenTiles: Set<Tile> = [
            Tile(.bamboo, 2), Tile(.bamboo, 3), Tile(.bamboo, 4),
            Tile(.bamboo, 6), Tile(.bamboo, 8), Tile(.honors, 6),
        ]
        if allTiles.allSatisfy({ greenTiles.contains($0) }) {
            yakuman.append(FanEntry(fan: .ryuuiisou))
        }
        if isMenzen && hand.melds.isEmpty && isChuurenPoutou(hand.concealed) {
            yakuman.append(FanEntry(fan: .chuurenPoutou))
        }
        if kongCount == 4 {
            yakuman.append(FanEntry(fan: .suukantsu))
        }
        return yakuman
    }

    private static func isChuurenPoutou(_ concealed: [Tile]) -> Bool {
        guard concealed.count == 14, let suit = concealed.first?.suit, suit != .honors else { return false }
        guard concealed.allSatisfy({ $0.suit == suit }) else { return false }
        var rankCounts = [Int](repeating: 0, count: 10)
        for t in concealed { rankCounts[t.rank] += 1 }
        guard rankCounts[1] >= 3, rankCounts[9] >= 3 else { return false }
        for r in 2...8 where rankCounts[r] < 1 { return false }
        return true
    }

    private static func appendSituationalYaku(to entries: inout [FanEntry], isMenzen: Bool, context: WinContext) {
        if isMenzen {
            if context.doubleRiichi {
                entries.append(FanEntry(fan: .doubleRiichi))
            } else if context.riichi {
                entries.append(FanEntry(fan: .riichi))
            }
            if (context.riichi || context.doubleRiichi) && context.ippatsu {
                entries.append(FanEntry(fan: .ippatsu))
            }
            if context.selfDrawn {
                entries.append(FanEntry(fan: .menzenTsumo))
            }
        }
        if context.kongInvolved {
            entries.append(FanEntry(fan: context.selfDrawn ? .rinshan : .chankan))
        } else if context.lastTileOfWall {
            entries.append(FanEntry(fan: context.selfDrawn ? .haitei : .houtei))
        }
    }

    private static func appendAllTileYaku(to entries: inout [FanEntry], allTiles: [Tile], isMenzen: Bool, isStandard: Bool) {
        if allTiles.allSatisfy(\.isSimple) {
            entries.append(FanEntry(fan: .tanyao))
        }
        if allTiles.allSatisfy(\.isTerminalOrHonor) && !allTiles.allSatisfy(\.isTerminal) && !allTiles.allSatisfy(\.isHonor) {
            entries.append(FanEntry(fan: .honroutou))
        }
        let suitedSuits = Set(allTiles.filter(\.isSuited).map(\.suit))
        let hasHonors = allTiles.contains(where: \.isHonor)
        if suitedSuits.count == 1 {
            if hasHonors {
                entries.append(makeEntry(.honitsu, isMenzen: isMenzen))
            } else {
                entries.append(makeEntry(.chinitsu, isMenzen: isMenzen))
            }
        }
    }

    private static func makeEntry(_ fan: Fan, isMenzen: Bool) -> FanEntry {
        let actual = fan.effectivePoints(isMenzen: isMenzen)
        return FanEntry(fan: fan, count: 1, han: actual == fan.points ? nil : actual)
    }
}
