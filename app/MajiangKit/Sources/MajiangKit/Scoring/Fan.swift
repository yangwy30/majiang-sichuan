import Foundation

/// 立直麻将役种（含役满）。宝牌（含赤宝牌、里宝牌）不计入起和役，单独记在 `ScoringResult.flowerFan`。
public enum Fan: Int, CaseIterable, Codable, Sendable {
    // 1 翻
    case riichi = 1
    case ippatsu
    case menzenTsumo
    case tanyao
    case pinfu
    case iipeiko
    case seatWind
    case prevalentWind
    case whiteDragon
    case greenDragon
    case redDragon
    case rinshan
    case chankan
    case haitei
    case houtei

    // 2 翻
    case doubleRiichi
    case sanshokuDoujun
    case ittsuu
    case chanta
    case chiitoitsu
    case toitoi
    case sanankou
    case sankantsu
    case sanshokuDoukou
    case honroutou
    case shousangen

    // 3 翻
    case ryanpeiko
    case junchan
    case honitsu

    // 6 翻
    case chinitsu

    // 役满（13 翻）
    case kokushi
    case suuankou
    case daisangen
    case shousuushii
    case daisuushii
    case tsuuiisou
    case chinroutou
    case ryuuiisou
    case chuurenPoutou
    case suukantsu
    case tenhou
    case chiihou

    // 兼容别名
    public static let fullFlush = Fan.chinitsu
    public static let halfFlush = Fan.honitsu
    public static let allPungs = Fan.toitoi
    public static let sevenPairs = Fan.chiitoitsu
    public static let selfDrawn = Fan.menzenTsumo
    public static let allSimples = Fan.tanyao
    public static let pureStraight = Fan.ittsuu
    public static let mixedTripleChow = Fan.sanshokuDoujun
    public static let pureDoubleChow = Fan.iipeiko
    public static let lastTileDraw = Fan.haitei
    public static let lastTileClaim = Fan.houtei
    public static let outWithReplacementTile = Fan.rinshan
    public static let robbingTheKong = Fan.chankan
    public static let chickenHand = Fan.riichi
    public static let allTypes = Fan.tanyao

    /// 门前清时的标准翻数（役满按 13 翻计）。
    public var points: Int {
        switch self {
        case .riichi, .ippatsu, .menzenTsumo, .tanyao, .pinfu, .iipeiko,
             .seatWind, .prevalentWind, .whiteDragon, .greenDragon, .redDragon,
             .rinshan, .chankan, .haitei, .houtei:
            return 1
        case .doubleRiichi, .sanshokuDoujun, .ittsuu, .chanta, .chiitoitsu,
             .toitoi, .sanankou, .sankantsu, .sanshokuDoukou, .honroutou, .shousangen:
            return 2
        case .ryanpeiko, .junchan, .honitsu:
            return 3
        case .chinitsu:
            return 6
        case .kokushi, .suuankou, .daisangen, .shousuushii, .daisuushii,
             .tsuuiisou, .chinroutou, .ryuuiisou, .chuurenPoutou, .suukantsu,
             .tenhou, .chiihou:
            return 13
        }
    }

    /// 副露（吃、碰、明杠）时的翻数；门前限定役返回 nil。
    public var openPoints: Int? {
        switch self {
        case .riichi, .ippatsu, .menzenTsumo, .pinfu, .iipeiko, .doubleRiichi,
             .chiitoitsu, .ryanpeiko, .kokushi, .suuankou, .chuurenPoutou, .tenhou, .chiihou:
            return nil
        case .sanshokuDoujun, .ittsuu, .chanta:
            return 1
        case .junchan, .honitsu:
            return 2
        case .chinitsu:
            return 5
        default:
            return points
        }
    }

    public var isYakuman: Bool { points == 13 }

    /// 实际计入的翻数（考虑是否门前清）。
    public func effectivePoints(isMenzen: Bool) -> Int {
        isMenzen ? points : (openPoints ?? points)
    }

    public var name: String {
        switch self {
        case .riichi: return "立直"
        case .ippatsu: return "一发"
        case .menzenTsumo: return "门前清自摸和"
        case .tanyao: return "断幺九"
        case .pinfu: return "平和"
        case .iipeiko: return "一杯口"
        case .seatWind: return "自风牌"
        case .prevalentWind: return "场风牌"
        case .whiteDragon: return "役牌·白"
        case .greenDragon: return "役牌·发"
        case .redDragon: return "役牌·中"
        case .rinshan: return "岭上开花"
        case .chankan: return "抢杠"
        case .haitei: return "海底摸月"
        case .houtei: return "河底捞鱼"
        case .doubleRiichi: return "双立直"
        case .sanshokuDoujun: return "三色同顺"
        case .ittsuu: return "一气通贯"
        case .chanta: return "混全带幺九"
        case .chiitoitsu: return "七对子"
        case .toitoi: return "对对和"
        case .sanankou: return "三暗刻"
        case .sankantsu: return "三杠子"
        case .sanshokuDoukou: return "三色同刻"
        case .honroutou: return "混老头"
        case .shousangen: return "小三元"
        case .ryanpeiko: return "二杯口"
        case .junchan: return "纯全带幺九"
        case .honitsu: return "混一色"
        case .chinitsu: return "清一色"
        case .kokushi: return "国士无双"
        case .suuankou: return "四暗刻"
        case .daisangen: return "大三元"
        case .shousuushii: return "小四喜"
        case .daisuushii: return "大四喜"
        case .tsuuiisou: return "字一色"
        case .chinroutou: return "清老头"
        case .ryuuiisou: return "绿一色"
        case .chuurenPoutou: return "九莲宝灯"
        case .suukantsu: return "四杠子"
        case .tenhou: return "天和"
        case .chiihou: return "地和"
        }
    }

    /// 一句话说清这个役怎么来的，给用户核对结果时看。
    public var explanation: String {
        switch self {
        case .riichi: return "门前清听牌时宣布立直"
        case .ippatsu: return "立直后一巡内和牌，中间没人吃碰杠"
        case .menzenTsumo: return "没吃碰明杠，自己摸到和牌"
        case .tanyao: return "整手牌全是 2–8 的数牌，没有一、九、字牌"
        case .pinfu: return "门前清四组顺子，雀头不是役牌，两面听牌"
        case .iipeiko: return "门前清有两组一模一样的顺子"
        case .seatWind: return "自己门风的一组刻子或杠"
        case .prevalentWind: return "本场风圈的一组刻子或杠"
        case .whiteDragon: return "白板的一组刻子或杠"
        case .greenDragon: return "发财的一组刻子或杠"
        case .redDragon: return "红中的一组刻子或杠"
        case .rinshan: return "开杠后摸上来的岭上牌自摸和了"
        case .chankan: return "别人加杠时，抢和那张牌"
        case .haitei: return "摸牌山最后一张牌自摸和了"
        case .houtei: return "和别人打出的全桌最后一张牌"
        case .doubleRiichi: return "第一巡还没人吃碰杠时就宣布立直"
        case .sanshokuDoujun: return "万、饼、条各有同一数字的顺子（副露减 1 翻）"
        case .ittsuu: return "同一花色有 123、456、789 三组顺子（副露减 1 翻）"
        case .chanta: return "每组顺子、刻子和雀头都带一、九或字牌（副露减 1 翻）"
        case .chiitoitsu: return "7 个不同的对子，固定 25 符"
        case .toitoi: return "4 组全是刻子或杠，没有顺子"
        case .sanankou: return "3 组自己摸来的暗刻或暗杠"
        case .sankantsu: return "开了 3 个杠"
        case .sanshokuDoukou: return "万、饼、条各有同一数字的刻子或杠"
        case .honroutou: return "整手牌只有一、九和字牌"
        case .shousangen: return "中、发、白里有两组刻子、一对雀头"
        case .ryanpeiko: return "门前清有两组一杯口（四组顺子两两相同）"
        case .junchan: return "每组顺子、刻子和雀头都带一或九，没有字牌（副露减 1 翻）"
        case .honitsu: return "只有一种数牌加字牌（副露减 1 翻）"
        case .chinitsu: return "全部是同一种数牌，没有字牌（副露减 1 翻）"
        case .kokushi: return "13 种幺九字牌各一张，再加其中任意一张成对"
        case .suuankou: return "4 组全是自己摸来的暗刻或暗杠"
        case .daisangen: return "中、发、白三组都是刻子或杠"
        case .shousuushii: return "东、南、西、北里有三组刻子、一对雀头"
        case .daisuushii: return "东、南、西、北四组都是刻子或杠"
        case .tsuuiisou: return "全部是东南西北中发白字牌"
        case .chinroutou: return "全部是 1 和 9 的数牌，没有字牌"
        case .ryuuiisou: return "全部由 2、3、4、6、8 条和发财组成"
        case .chuurenPoutou: return "门前清同花色 1112345678999 加同花色任意一张"
        case .suukantsu: return "开了 4 个杠"
        case .tenhou: return "庄家第一巡配牌直接自摸和牌"
        case .chiihou: return "闲家第一巡还没人吃碰杠时自摸和牌"
        }
    }
}

public struct FanEntry: Hashable, Codable, Sendable {
    public let fan: Fan
    public let count: Int
    /// 副露减翻时记录实际翻数；nil 时按 `fan.points * count`。
    public var han: Int?

    public init(fan: Fan, count: Int = 1, han: Int? = nil) {
        self.fan = fan
        self.count = count
        self.han = han
    }

    public var points: Int { han ?? (fan.points * count) }
}
