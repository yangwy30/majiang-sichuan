import Foundation

/// 照片拍不出来、要用户在核对页勾一下的情况（立直、一发、双立直、岭上开花、海底、河底、抢杠）。
public enum SpecialWin: String, CaseIterable, Hashable, Codable, Sendable {
    /// 立直：门前清听牌宣布立直，1 翻。
    case riichi
    /// 一发：立直后一巡内和牌，1 翻。
    case ippatsu
    /// 双立直：第一巡无人副露时宣布立直，2 翻。
    case doubleRiichi
    /// 岭上开花：开杠后补牌自摸，1 翻。
    case kongReplacement
    /// 海底摸月：牌山最后一张自摸，1 翻。
    case lastTileDraw
    /// 河底捞鱼：全桌最后一张点炮和牌，1 翻。
    case lastTileClaim
    /// 抢杠：别人加杠时抢和，1 翻。
    case robbingTheKong

    public var name: String {
        switch self {
        case .riichi: return "立直"
        case .ippatsu: return "一发"
        case .doubleRiichi: return "双立直"
        case .kongReplacement: return "岭上开花"
        case .lastTileDraw: return "海底摸月"
        case .lastTileClaim: return "河底捞鱼"
        case .robbingTheKong: return "抢杠"
        }
    }

    public var fan: Fan {
        switch self {
        case .riichi: return .riichi
        case .ippatsu: return .ippatsu
        case .doubleRiichi: return .doubleRiichi
        case .kongReplacement: return .rinshan
        case .lastTileDraw: return .haitei
        case .lastTileClaim: return .houtei
        case .robbingTheKong: return .chankan
        }
    }

    /// 勾选上这一项加几翻。
    public var fanPoints: Int { fan.points }

    /// 一句白话说明。
    public var plain: String {
        switch self {
        case .riichi: return "门前清听牌时宣布了立直"
        case .ippatsu: return "立直后一巡内和牌，中间没人吃碰杠"
        case .doubleRiichi: return "第一巡还没人吃碰杠时就立直了"
        case .kongReplacement: return "杠完摸岭上牌，正好自摸和了"
        case .lastTileDraw: return "摸牌山最后一张牌时自摸和了"
        case .lastTileClaim: return "和的是别人打出的最后一张牌"
        case .robbingTheKong: return "别人加杠时，正好抢和他加的那张"
        }
    }

    /// 这手牌下能不能选；不能选时返回原因（界面用来置灰）。
    public func unavailableReason(hand: Hand, selfDrawn: Bool) -> String? {
        let isMenzen = hand.melds.allSatisfy { $0.kind == .kong && $0.isConcealed }
        switch self {
        case .riichi, .ippatsu, .doubleRiichi:
            guard isMenzen else { return "有吃、碰、明杠时不能立直" }
            return nil
        case .kongReplacement:
            guard selfDrawn else { return "岭上开花只能是自摸" }
            guard hand.melds.contains(where: { $0.kind == .kong }) else { return "这手牌没有杠" }
            return nil
        case .lastTileDraw:
            return selfDrawn ? nil : "海底摸月只能是自摸"
        case .lastTileClaim:
            return selfDrawn ? "河底捞鱼只能是点炮" : nil
        case .robbingTheKong:
            guard !selfDrawn else { return "抢杠只能是点炮" }
            let ownCopies = hand.allTiles.filter { $0 == hand.winningTile }.count
            return ownCopies > 1 ? "手牌里已经有 \(ownCopies) 张 \(hand.winningTile.displayName)，别人没法加杠这张" : nil
        }
    }

    /// 跟这一项不能同时选的（选了新的就把冲突的旧项替掉）。
    public var conflicts: Set<SpecialWin> {
        switch self {
        case .riichi: return [.doubleRiichi]
        case .doubleRiichi: return [.riichi]
        case .ippatsu: return []
        case .kongReplacement: return [.lastTileDraw, .lastTileClaim, .robbingTheKong]
        case .lastTileDraw: return [.kongReplacement, .lastTileClaim, .robbingTheKong]
        case .lastTileClaim: return [.kongReplacement, .lastTileDraw, .robbingTheKong]
        case .robbingTheKong: return [.kongReplacement, .lastTileDraw, .lastTileClaim]
        }
    }

    public static func apply(_ set: Set<SpecialWin>, to context: inout WinContext) {
        context.doubleRiichi = set.contains(.doubleRiichi)
        context.riichi = set.contains(.riichi) || (set.contains(.ippatsu) && !set.contains(.doubleRiichi))
        context.ippatsu = set.contains(.ippatsu)
        context.lastTileOfWall = set.contains(.lastTileDraw) || set.contains(.lastTileClaim)
        context.kongInvolved = set.contains(.kongReplacement) || set.contains(.robbingTheKong)
    }

    public static func from(_ context: WinContext) -> Set<SpecialWin> {
        var result: Set<SpecialWin> = []
        if context.doubleRiichi {
            result.insert(.doubleRiichi)
        } else if context.riichi {
            result.insert(.riichi)
        }
        if context.ippatsu { result.insert(.ippatsu) }
        if context.lastTileOfWall { result.insert(context.selfDrawn ? .lastTileDraw : .lastTileClaim) }
        if context.kongInvolved { result.insert(context.selfDrawn ? .kongReplacement : .robbingTheKong) }
        return result
    }
}

/// 改一张牌（或补一张漏读的牌）就能和的建议。
public struct FixSuggestion: Hashable, Sendable {
    /// `concealed` 里的下标；nil 表示不是改某一张，而是补一张。
    public let index: Int?
    public let from: Tile?
    public let to: Tile
    public let result: ScoringResult

    /// 拍照识别最容易把同花色点数看差一两点，排在前面。
    var distance: Int {
        guard let from else { return 0 }
        if from.suit == to.suit { return from.isHonor ? 3 : abs(from.rank - to.rank) }
        return 10
    }
}

public enum WinAssistant {
    /// 和不了时用人话告诉用户为什么。能和时返回 nil。
    public static func explain(_ hand: Hand, context: WinContext = WinContext(), minimumFan: Int = 1) -> String? {
        switch FanCalculator.score(hand, context: context) {
        case .success(let result):
            if result.meetsMinimum(minimumFan) { return nil }
            let doraNote = result.flowerFan > 0 ? "（宝牌 \(result.flowerFan) 翻不算进起和役）" : ""
            if result.fanWithoutFlowers == 0 {
                return "无役\(doraNote)，立直麻将至少要有 \(minimumFan) 翻役才能和。"
            }
            return "只有 \(result.fanWithoutFlowers) 翻役\(doraNote)，本场要 \(minimumFan) 翻才能和。"
        case .failure(.wrongTileCount):
            let expected = 14 - hand.melds.count * 3
            return "张数不对：立牌应该是 \(expected) 张，现在是 \(hand.concealed.count) 张。"
        case .failure(.tileMoreThanFour):
            let names = hand.overusedTiles.map(\.displayName).joined(separator: "、")
            return "\(names) 超过了 4 张，一定有牌认错了。"
        case .failure(.notAWin):
            return "这副牌凑不成和牌（需要 4 面子加 1 雀头，或七对子、国士无双）。"
        }
    }

    /// 识别差一张导致和不了时，找出改哪一张（或补哪一张）就能和。
    /// 如果牌型本身已经成立、只是无役，不给改牌建议（牌可能没认错，是漏选了立直或真的无役）。
    public static func fixSuggestions(for hand: Hand, context: WinContext = WinContext(),
                                      minimumFan: Int = 1, limit: Int = 4) -> [FixSuggestion] {
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
