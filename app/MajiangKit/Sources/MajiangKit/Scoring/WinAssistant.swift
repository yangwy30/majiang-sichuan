import Foundation

/// 照片拍不出来、要用户在核对页勾一下的川麻特殊胡牌情况（杠上开花、杠上炮、抢杠胡、海底捞月、海底炮、天胡、地胡）。
public enum SpecialWin: String, CaseIterable, Hashable, Codable, Sendable {
    /// 杠上开花：开杠后补牌自摸，+1 番。
    case kongReplacement
    /// 杠上炮：开杠后打牌点炮，+1 番，且触发呼叫转移（刚才收的杠钱转给胡牌者）。
    case kongPao
    /// 抢杠胡：别人巴杠（弯杠）时抢胡，+1 番。
    case robbingTheKong
    /// 海底捞月：牌墙最后一张自摸，+1 番。
    case lastTileDraw
    /// 海底炮：最后一张点炮胡牌，+1 番。
    case lastTileClaim
    /// 天胡：庄家起手配牌直接胡，+5 番（直接封顶）。
    case tianHu
    /// 地胡：闲家第一巡摸牌直接胡，+5 番（直接封顶）。
    case diHu

    public var name: String {
        switch self {
        case .kongReplacement: return "杠上开花"
        case .kongPao: return "杠上炮（呼叫转移）"
        case .robbingTheKong: return "抢杠胡"
        case .lastTileDraw: return "海底捞月"
        case .lastTileClaim: return "海底炮"
        case .tianHu: return "天胡"
        case .diHu: return "地胡"
        }
    }

    public var fan: Fan {
        switch self {
        case .kongReplacement: return .gangShangHua
        case .kongPao: return .gangShangPao
        case .robbingTheKong: return .qiangGangHu
        case .lastTileDraw: return .haiDiLaoYue
        case .lastTileClaim: return .haiDiPao
        case .tianHu: return .tianHu
        case .diHu: return .diHu
        }
    }

    /// 勾选上这一项加几番。
    public var fanPoints: Int { fan.points }

    /// 一句白话说明。
    public var plain: String {
        switch self {
        case .kongReplacement: return "开杠后摸上来的补张牌正好胡了"
        case .kongPao: return "别人开杠后打出的牌点炮，他刚收的杠钱自动转给你"
        case .robbingTheKong: return "别人巴杠（弯杠）时，抢胡他加杠的那张牌"
        case .lastTileDraw: return "摸牌墙最后一张牌自摸胡了"
        case .lastTileClaim: return "牌墙摸完后，别人打出的最后一张点炮"
        case .tianHu: return "庄家起手 14 张牌直接胡牌"
        case .diHu: return "闲家第一巡摸牌直接胡牌"
        }
    }

    /// 这手牌下能不能选；不能选时返回原因（界面用来置灰）。
    public func unavailableReason(hand: Hand, selfDrawn: Bool, allowDianGangPao: Bool = false) -> String? {
        switch self {
        case .kongReplacement:
            if !selfDrawn && !allowDianGangPao {
                return "杠上开花一般算自摸（除非桌规设点杠花算点炮）"
            }
            return nil
        case .kongPao:
            return selfDrawn ? "杠上炮只能是别人点炮" : nil
        case .robbingTheKong:
            guard !selfDrawn else { return "抢杠胡只能是点炮" }
            let ownCopies = hand.allTiles.filter { $0 == hand.winningTile }.count
            return ownCopies > 1 ? "手牌里已经有 \(ownCopies) 张 \(hand.winningTile.displayName)，别人没法巴杠这张" : nil
        case .lastTileDraw:
            return selfDrawn ? nil : "海底捞月只能是自摸"
        case .lastTileClaim:
            return selfDrawn ? "海底炮只能是点炮" : nil
        case .tianHu:
            guard selfDrawn else { return "天胡只能是自摸" }
            guard hand.melds.isEmpty else { return "有碰杠时不能算天胡" }
            return nil
        case .diHu:
            guard hand.melds.isEmpty else { return "有碰杠时不能算地胡" }
            return nil
        }
    }

    /// 跟这一项不能同时选的（选了新的就把冲突的旧项替掉）。
    public var conflicts: Set<SpecialWin> {
        switch self {
        case .kongReplacement: return [.kongPao, .robbingTheKong, .lastTileDraw, .lastTileClaim, .tianHu, .diHu]
        case .kongPao: return [.kongReplacement, .robbingTheKong, .lastTileDraw, .lastTileClaim, .tianHu, .diHu]
        case .robbingTheKong: return [.kongReplacement, .kongPao, .lastTileDraw, .lastTileClaim, .tianHu, .diHu]
        case .lastTileDraw: return [.kongReplacement, .kongPao, .robbingTheKong, .lastTileClaim, .tianHu, .diHu]
        case .lastTileClaim: return [.kongReplacement, .kongPao, .robbingTheKong, .lastTileDraw, .tianHu, .diHu]
        case .tianHu: return [.kongReplacement, .kongPao, .robbingTheKong, .lastTileDraw, .lastTileClaim, .diHu]
        case .diHu: return [.kongReplacement, .kongPao, .robbingTheKong, .lastTileDraw, .lastTileClaim, .tianHu]
        }
    }

    public static func apply(_ set: Set<SpecialWin>, to context: inout WinContext) {
        context.gangShangHua = set.contains(.kongReplacement)
        context.gangShangPao = set.contains(.kongPao)
        context.qiangGangHu = set.contains(.robbingTheKong)
        context.lastTileOfWall = set.contains(.lastTileDraw) || set.contains(.lastTileClaim)
        context.tianHu = set.contains(.tianHu)
        context.diHu = set.contains(.diHu)
    }

    public static func from(_ context: WinContext) -> Set<SpecialWin> {
        var result: Set<SpecialWin> = []
        if context.gangShangHua { result.insert(.kongReplacement) }
        if context.gangShangPao { result.insert(.kongPao) }
        if context.qiangGangHu { result.insert(.robbingTheKong) }
        if context.lastTileOfWall { result.insert(context.selfDrawn ? .lastTileDraw : .lastTileClaim) }
        if context.tianHu { result.insert(.tianHu) }
        if context.diHu { result.insert(.diHu) }
        return result
    }
}

public typealias HandFix = FixSuggestion

/// 改一张牌（或补一张漏读的牌）就能胡的建议。
public struct FixSuggestion: Identifiable, Hashable, Sendable {
    /// `concealed` 里的下标；nil 表示不是改某一张，而是补一张。
    public let index: Int?
    public let from: Tile?
    public let to: Tile
    public let result: ScoringResult

    public var id: String { "\(index ?? -1)-\(to.notation)" }
    public var topFanName: String { result.fans.first?.fan.name ?? "平胡" }
    public var totalFan: Int { result.totalFan }

    /// 拍照识别最容易把同花色点数看差一两点，排在前面。
    var distance: Int {
        guard let from else { return 0 }
        if from.suit == to.suit { return from.isHonor ? 3 : abs(from.rank - to.rank) }
        return 10
    }
}

/// 流局 13 张手牌「查花猪 / 查大叫」结果。
public struct TingCheckResult: Hashable, Codable, Sendable {
    public enum Status: String, Hashable, Codable, Sendable {
        /// 花猪：万、筒、条三门俱全（直接按封顶番数赔给所有非花猪玩家，并退还本局杠钱）。
        case huaZhu
        /// 未下叫（未听牌）：已缺一门，但凑不成任何听牌（退还本局杠钱，并向已下叫玩家赔大叫）。
        case notTing
        /// 已下叫（已听牌）：穷举所有可胡牌张，算出最高可能胡牌番数（大叫）。
        case ting
    }

    public struct WaitOption: Hashable, Codable, Sendable {
        public let tile: Tile
        public let result: ScoringResult
        public var totalFan: Int { result.totalFan }
        public var baseMultiplier: Int { result.baseMultiplier }

        public init(tile: Tile, result: ScoringResult) {
            self.tile = tile
            self.result = result
        }
    }

    public let status: Status
    /// 所有可胡牌张及对应番型（按番数从高到低排列）。
    public let waits: [WaitOption]

    public init(status: Status, waits: [WaitOption] = []) {
        self.status = status
        self.waits = waits
    }

    /// 最高可能胡牌番型（大叫）。
    public var bestWait: WaitOption? { waits.first }

    /// 大叫番数（未下叫或花猪时为 0）。
    public var maxFan: Int { bestWait?.totalFan ?? 0 }

    /// 一句话总结查叫结果，供界面直接展示。
    public var summaryText: String {
        switch status {
        case .huaZhu:
            return "花猪（万筒条三门俱全）· 赔封顶番并退税"
        case .notTing:
            return "未下叫（未听牌）· 退还本局杠钱并赔大叫"
        case .ting:
            guard let best = bestWait else { return "已下叫" }
            let fanName = best.result.fans.first?.fan.name ?? "平胡"
            let tilesText = waits.map(\.tile.displayName).joined(separator: "、")
            return "已下叫 · 大叫 \(best.totalFan) 番（\(fanName)，\(best.baseMultiplier) 倍）· 听 \(tilesText)"
        }
    }
}

public enum WinAssistant {
    /// 流局「查花猪 / 查大叫」求解器：输入未胡牌者的 13 张牌（含副露），自动判花猪或穷举最大可能番数（大叫）。
    public static func checkTing(
        melds: [Meld] = [],
        standing: [Tile],
        allowMenQing: Bool = false,
        allowZhongZhang: Bool = false
    ) -> TingCheckResult {
        let allTiles = melds.flatMap(\.tiles) + standing
        let suits = Set(allTiles.filter(\.isNumbered).map(\.suit))
        if suits.count >= 3 || allTiles.contains(where: \.isHonor) {
            return TingCheckResult(status: .huaZhu, waits: [])
        }

        guard melds.count * 3 + standing.count == 13, melds.allSatisfy(\.isValid) else {
            return TingCheckResult(status: .notTing, waits: [])
        }

        let used = Dictionary(grouping: allTiles, by: { $0 }).mapValues(\.count)
        guard used.values.allSatisfy({ $0 <= 4 }) else {
            return TingCheckResult(status: .notTing, waits: [])
        }

        let context = WinContext(
            selfDrawn: false,
            allowMenQing: allowMenQing,
            allowZhongZhang: allowZhongZhang,
            selfDrawnAddFan: false
        )

        var waits: [TingCheckResult.WaitOption] = []
        for candidate in Tile.all {
            guard (used[candidate] ?? 0) < 4 else { continue }
            let hand = Hand(melds: melds, concealed: standing + [candidate], winningTile: candidate)
            if case .success(let result) = FanCalculator.score(hand, context: context) {
                waits.append(TingCheckResult.WaitOption(tile: candidate, result: result))
            }
        }

        waits.sort { lhs, rhs in
            if lhs.totalFan != rhs.totalFan { return lhs.totalFan > rhs.totalFan }
            return lhs.tile < rhs.tile
        }

        if waits.isEmpty {
            return TingCheckResult(status: .notTing, waits: [])
        }
        return TingCheckResult(status: .ting, waits: waits)
    }

    /// 便捷重载：直接传入 13 张手牌 `Hand`。
    public static func checkTing(
        _ hand: Hand,
        allowMenQing: Bool = false,
        allowZhongZhang: Bool = false
    ) -> TingCheckResult {
        checkTing(
            melds: hand.melds,
            standing: hand.concealed,
            allowMenQing: allowMenQing,
            allowZhongZhang: allowZhongZhang
        )
    }

    /// 便捷重载：直接传入 13 张手牌 `Hand` 与本桌规则 `GameRules`（自动带上门清、中张设置）。
    public static func checkTing(_ hand: Hand, rules: GameRules) -> TingCheckResult {
        checkTing(
            melds: hand.melds,
            standing: hand.concealed,
            allowMenQing: rules.allowMenQing,
            allowZhongZhang: rules.allowZhongZhang
        )
    }

    /// 对一个 `Hand`（13 张或 14 张）直接查花猪/查大叫。若传入 14 张则自动去掉最后一张按 13 张查叫。
    public static func checkTing(
        hand: Hand,
        allowMenQing: Bool = false,
        allowZhongZhang: Bool = false
    ) -> TingCheckResult {
        if hand.isHuaZhu {
            return TingCheckResult(status: .huaZhu, waits: [])
        }
        let expected = 13 - hand.melds.count * 3
        let standing: [Tile]
        if hand.concealed.count == expected {
            standing = hand.concealed
        } else if hand.concealed.count == expected + 1 {
            standing = Array(hand.concealed.dropLast())
        } else {
            return TingCheckResult(status: .notTing, waits: [])
        }
        return checkTing(melds: hand.melds, standing: standing, allowMenQing: allowMenQing, allowZhongZhang: allowZhongZhang)
    }

    /// 胡不了时用人话告诉用户为什么。能胡时返回 nil。
    public static func explain(_ hand: Hand, context: WinContext = WinContext(), minimumFan: Int = 0) -> String? {
        switch FanCalculator.score(hand, context: context) {
        case .success(let result):
            if result.meetsMinimum(minimumFan) { return nil }
            return "只有 \(result.totalFan) 番，本场要 \(minimumFan) 番起胡。"
        case .failure(.wrongTileCount):
            let expected = 14 - hand.melds.count * 3
            return "张数不对：立牌应该是 \(expected) 张，现在是 \(hand.concealed.count) 张。"
        case .failure(.tileMoreThanFour):
            let names = hand.overusedTiles.map(\.displayName).joined(separator: "、")
            return "\(names) 超过了 4 张，一定有牌认错了。"
        case .failure(.missingSuitRequired):
            return "花猪（万、筒、条三门俱全）：四川麻将必须缺一门才能胡牌。"
        case .failure(.notAWin):
            return "这副牌凑不成胡牌（需要缺一门，且凑成 4 面子加 1 对将，或七对）。"
        }
    }

    /// 识别差一张导致胡不了时，找出改哪一张（或补哪一张）就能胡。
    public static func fixSuggestions(for hand: Hand, context: WinContext = WinContext(),
                                      minimumFan: Int = 0, limit: Int = 4) -> [FixSuggestion] {
        guard hand.melds.allSatisfy(\.isValid) else { return [] }
        let expected = 14 - hand.melds.count * 3

        if hand.concealed.count == expected - 1 {
            return FanCalculator.waitingTiles(melds: hand.melds, standing: hand.concealed).compactMap { tile in
                let candidate = Hand(melds: hand.melds, concealed: hand.concealed + [tile], winningTile: tile)
                guard case .success(let result) = FanCalculator.score(candidate, context: context),
                      result.meetsMinimum(minimumFan) else { return nil }
                return FixSuggestion(index: nil, from: nil, to: tile, result: result)
            }
        }

        guard hand.concealed.count == expected else { return [] }
        if FanCalculator.isWinningShape(hand) { return [] }

        var suggestions: [FixSuggestion] = []
        let used = Dictionary(grouping: hand.allTiles, by: { $0 }).mapValues(\.count)
        let winIsLast = hand.concealed.last == hand.winningTile

        for i in hand.concealed.indices {
            let original = hand.concealed[i]
            for replacement in Tile.all where replacement != original {
                if (used[replacement] ?? 0) >= 4 { continue }
                var copy = hand.concealed
                copy[i] = replacement
                let win = (i == copy.count - 1 && winIsLast) ? replacement : hand.winningTile
                let candidate = Hand(melds: hand.melds, concealed: copy, winningTile: win)
                guard case .success(let result) = FanCalculator.score(candidate, context: context),
                      result.meetsMinimum(minimumFan) else { continue }
                suggestions.append(FixSuggestion(index: i, from: original, to: replacement, result: result))
            }
        }

        suggestions.sort { ($0.distance, $0.index ?? 0) < ($1.distance, $1.index ?? 0) }
        var seen = Set<Int>()
        return suggestions.filter { s in
            guard let i = s.index else { return true }
            return seen.insert(i).inserted
        }
        .prefix(limit)
        .map { $0 }
    }
}
