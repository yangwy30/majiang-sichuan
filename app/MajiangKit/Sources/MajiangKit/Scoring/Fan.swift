import Foundation

/// 四川麻将（血战到底 / 血流成河）番型与加番项。
/// 倍数按 $2^{\text{番数}}$ 计算（0 番平胡 = 1 倍，1 番 = 2 倍，2 番 = 4 倍，3 番 = 8 倍，4 番 = 16 倍，5 番 = 32 倍……）。
public enum Fan: Int, CaseIterable, Codable, Sendable {
    // 基础牌型番（0 番 — 6 番）
    case pingHu = 0          // 平胡（基本胡，0 番 1 倍）
    case duiDuiHu = 1        // 对对胡（碰碰胡，1 番 2 倍）
    case qingYiSe = 2        // 清一色（2 番 4 倍）
    case qiDui = 3           // 七对（暗七对，2 番 4 倍）
    case daiYaoJiu = 4       // 带幺九（全带幺，2 番 4 倍）
    case jinGouDiao = 5      // 金钩钓（对对胡 + 单吊将，2 番 4 倍）
    case jiangDui = 6        // 将对（258 对对胡，3 番 8 倍）
    case qingDui = 7         // 清对（清一色 + 对对胡，3 番 8 倍）
    case longQiDui = 8       // 龙七对（带 1 根的七对，3 番 8 倍，该根不重复计）
    case qingQiDui = 9       // 清七对（清一色 + 七对，4 番 16 倍）
    case qingDaiYao = 10     // 清带幺（清一色 + 带幺九，4 番 16 倍）
    case qingJinGouDiao = 11 // 清金钩钓（清一色 + 金钩钓，4 番 16 倍）
    case jiangJinGou = 12    // 将金钩（将对 + 金钩钓，4 番 16 倍）
    case qingLongQiDui = 13  // 清龙七对（清一色 + 龙七对，5 番 32 倍，首根不重复计）
    case tianHu = 14         // 天胡（庄家起手胡，5 番 32 倍）
    case diHu = 15           // 地胡（闲家首巡胡，5 番 32 倍）
    case shiBaLuoHan = 16    // 十八罗汉（四杠金钩钓，6 番 64 倍）

    // 叠加加番项（每项 +1 番，即翻倍）
    case gen = 17            // 根（每有 4 张相同的牌 +1 番）
    case gangShangHua = 18   // 杠上开花（开杠补牌自摸 +1 番）
    case gangShangPao = 19   // 杠上炮（开杠后打牌点炮 +1 番，触发呼叫转移）
    case qiangGangHu = 20    // 抢杠胡（抢别人巴杠/弯杠 +1 番）
    case haiDiLaoYue = 21    // 海底捞月（最后一张自摸 +1 番）
    case haiDiPao = 22       // 海底炮（最后一张点炮 +1 番）
    case menQing = 23        // 门清（家规开启时，无碰无明杠 +1 番）
    case zhongZhang = 24     // 中张 / 断幺九（家规开启时，全 2–8 无幺九 +1 番）
    case ziMoJiaFan = 25     // 自摸加番（家规选「自摸加番」时 +1 番）

    // 兼容旧代码别名
    public static let fullFlush = Fan.qingYiSe
    public static let allPungs = Fan.duiDuiHu
    public static let sevenPairs = Fan.qiDui
    public static let chickenHand = Fan.pingHu
    public static let allSimples = Fan.zhongZhang
    public static let outWithReplacementTile = Fan.gangShangHua
    public static let robbingTheKong = Fan.qiangGangHu
    public static let lastTileDraw = Fan.haiDiLaoYue
    public static let lastTileClaim = Fan.haiDiPao

    /// 该番型对应的番数。
    public var points: Int {
        switch self {
        case .pingHu:
            return 0
        case .duiDuiHu, .gen, .gangShangHua, .gangShangPao, .qiangGangHu,
             .haiDiLaoYue, .haiDiPao, .menQing, .zhongZhang, .ziMoJiaFan:
            return 1
        case .qingYiSe, .qiDui, .daiYaoJiu, .jinGouDiao:
            return 2
        case .jiangDui, .qingDui, .longQiDui:
            return 3
        case .qingQiDui, .qingDaiYao, .qingJinGouDiao, .jiangJinGou:
            return 4
        case .qingLongQiDui, .tianHu, .diHu:
            return 5
        case .shiBaLuoHan:
            return 6
        }
    }

    /// 是否为封顶大番（天胡、地胡、十八罗汉、清龙七对）。
    public var isLimitFan: Bool {
        points >= 5
    }

    public var isYakuman: Bool { isLimitFan }

    public var name: String {
        switch self {
        case .pingHu: return "平胡"
        case .duiDuiHu: return "对对胡"
        case .qingYiSe: return "清一色"
        case .qiDui: return "七对"
        case .daiYaoJiu: return "带幺九"
        case .jinGouDiao: return "金钩钓"
        case .jiangDui: return "将对"
        case .qingDui: return "清对"
        case .longQiDui: return "龙七对"
        case .qingQiDui: return "清七对"
        case .qingDaiYao: return "清带幺"
        case .qingJinGouDiao: return "清金钩钓"
        case .jiangJinGou: return "将金钩"
        case .qingLongQiDui: return "清龙七对"
        case .tianHu: return "天胡"
        case .diHu: return "地胡"
        case .shiBaLuoHan: return "十八罗汉"
        case .gen: return "根"
        case .gangShangHua: return "杠上开花"
        case .gangShangPao: return "杠上炮"
        case .qiangGangHu: return "抢杠胡"
        case .haiDiLaoYue: return "海底捞月"
        case .haiDiPao: return "海底炮"
        case .menQing: return "门清"
        case .zhongZhang: return "中张"
        case .ziMoJiaFan: return "自摸加番"
        }
    }

    /// 一句话白话说明，给用户核对结果或看番种速查时用。
    public var explanation: String {
        switch self {
        case .pingHu: return "缺一门，4 组顺子或刻子加 1 对将（0 番 1 倍）"
        case .duiDuiHu: return "4 组全部是刻子或杠，加 1 对将（1 番 2 倍）"
        case .qingYiSe: return "整手牌全部是同一花色（2 番 4 倍）"
        case .qiDui: return "门前清 7 个对子，没有碰和杠（2 番 4 倍）"
        case .daiYaoJiu: return "每一组顺子、刻子和将牌都带有 1 或 9（2 番 4 倍）"
        case .jinGouDiao: return "4 组全部碰或杠亮在桌上，手牌只剩单吊 1 张将（2 番 4 倍）"
        case .jiangDui: return "全部由 2、5、8 组成的对对胡（3 番 8 倍）"
        case .qingDui: return "清一色 + 对对胡（3 番 8 倍）"
        case .longQiDui: return "七对里含有 4 张一样的牌（3 番 8 倍，自带的 1 根不重复算）"
        case .qingQiDui: return "清一色 + 七对（4 番 16 倍）"
        case .qingDaiYao: return "清一色 + 带幺九（4 番 16 倍）"
        case .qingJinGouDiao: return "清一色 + 金钩钓（4 番 16 倍）"
        case .jiangJinGou: return "将对 + 金钩钓，全 2、5、8 单吊将（4 番 16 倍）"
        case .qingLongQiDui: return "清一色 + 龙七对（5 番 32 倍，自带的 1 根不重复算）"
        case .tianHu: return "庄家起手配牌 14 张直接胡牌"
        case .diHu: return "闲家第一巡摸牌直接胡牌"
        case .shiBaLuoHan: return "开了 4 个杠 + 金钩钓单吊将（6 番 64 倍）"
        case .gen: return "整手牌（含碰、杠、立牌）每有 4 张相同的牌加 1 番"
        case .gangShangHua: return "开杠后摸上来的补张牌自摸胡了（+1 番）"
        case .gangShangPao: return "开杠后打出的牌点炮，+1 番且刚才收的杠钱呼叫转移给胡牌者"
        case .qiangGangHu: return "别人巴杠（弯杠）时，抢胡他加杠的那张牌（+1 番）"
        case .haiDiLaoYue: return "摸牌墙最后一张牌自摸胡了（+1 番）"
        case .haiDiPao: return "牌墙摸完后，打出的最后一张牌点炮（+1 番）"
        case .menQing: return "没碰、没明杠，全靠自己摸牌胡牌（+1 番，需桌规开启）"
        case .zhongZhang: return "整手牌全是 2–8，没有 1 和 9（+1 番，需桌规开启）"
        case .ziMoJiaFan: return "桌规设为「自摸加番」时，自摸额外 +1 番（翻倍）"
        }
    }
}

public struct FanEntry: Hashable, Codable, Sendable {
    public let fan: Fan
    public let count: Int
    public var han: Int?

    public init(fan: Fan, count: Int = 1, han: Int? = nil) {
        self.fan = fan
        self.count = count
        self.han = han
    }

    public var points: Int { han ?? (fan.points * count) }
}
