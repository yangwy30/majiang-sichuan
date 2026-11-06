import Foundation

public struct Player: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// 四川麻将玩法模式。
public enum SichuanMode: String, Codable, CaseIterable, Sendable {
    /// 血战到底：一局内最多 3 人先后胡牌，胡牌玩家离场，后续刮风下雨与胡牌只在未胡在场玩家间收付。
    case xuezhan
    /// 血流成河：胡牌后继续留在场上打牌（手牌锁定），一局内可连胡多次，牌摸完后结算。
    case xueliu

    public var name: String {
        switch self {
        case .xuezhan: return "血战到底"
        case .xueliu: return "血流成河"
        }
    }

    public var shortName: String {
        switch self {
        case .xuezhan: return "血战"
        case .xueliu: return "血流"
        }
    }
}

/// 自摸算法。
public enum ZimoRule: String, Codable, CaseIterable, Sendable {
    /// 自摸加底（成都主流）：总倍数 $+1$（如平胡自摸 $1+1=2$ 倍，清一色自摸 $4+1=5$ 倍）。
    case addDi
    /// 自摸加番：总番数 $+1$（即翻倍，受封顶番数限制）。
    case addFan

    public var name: String {
        switch self {
        case .addDi: return "自摸加底"
        case .addFan: return "自摸加番"
        }
    }
}

/// 点杠花（直杠别人后补牌自摸）算法。
public enum DianGangHuaRule: String, Codable, CaseIterable, Sendable {
    /// 点杠花算自摸：在场未胡各家都要付。
    case asZimo
    /// 点杠花算点炮：由点杠者一家包付。
    case asDianPao

    public var name: String {
        switch self {
        case .asZimo: return "点杠花算自摸"
        case .asDianPao: return "点杠花算点炮"
        }
    }
}

/// 四川麻将牌局规则（默认成都主流：血战到底、4 番 16 倍封顶、自摸加底、点杠花算自摸）。
public struct GameRules: Hashable, Codable, Sendable {
    /// 玩法模式：血战到底 vs 血流成河。
    public var mode: SichuanMode = .xuezhan
    /// 封顶番数：3（8 倍）/ 4（16 倍，默认）/ 5（32 倍）/ 0（不封顶）。
    public var fanCap: Int = 4
    /// 自摸算法：自摸加底（默认） vs 自摸加番。
    public var zimoRule: ZimoRule = .addDi
    /// 点杠花算法：点杠花算自摸（默认） vs 点杠花算点炮。
    public var dianGangHuaRule: DianGangHuaRule = .asZimo
    /// 门清是否算 +1 番。
    public var allowMenQing: Bool = false
    /// 中张（断幺九，全 2–8）是否算 +1 番。
    public var allowZhongZhang: Bool = false
    /// 每底多少分（默认 1 分/底）。
    public var basePoints: Int = 1
    /// 每 1 分折合多少元（默认 1 分 = 1 元）。
    public var yuanPerPoint: Double = 1
    /// 起胡番数（默认 0 番平胡即可起胡；少数桌规要求 1 番起胡）。
    public var minimumFan: Int = 0
    /// 一场打几局（默认 8 局）。
    public var totalHands: Int = 8
    /// 诈胡（错和）赔在场每家多少分（默认 16 分）。
    public var falseWinPenalty: Int = 16
    /// 每圈换座；朋友局一般不换。
    public var swapSeatsEachRound: Bool = false

    // 兼容字段
    public var includeFlowers: Bool = false
    public var kiriageMangan: Bool = false
    public var onlyDiscarderPays: Bool = true

    public init() {}

    /// 标准血战到底（成都主流：4 番 16 倍封顶、自摸加底、点杠花算自摸）。
    public static let standard = GameRules()

    /// 血流成河预设（4 番 16 倍封顶、自摸加底、门清中张开启）。
    public static var xueliuStandard: GameRules {
        var rules = GameRules()
        rules.mode = .xueliu
        rules.allowMenQing = true
        rules.allowZhongZhang = true
        return rules
    }

    public static var xueliu: GameRules { xueliuStandard }

    /// 血战加番（5 番 32 倍封顶、自摸加番、门清中张开启）。
    public static var highCap: GameRules {
        var rules = GameRules()
        rules.mode = .xuezhan
        rules.fanCap = 5
        rules.zimoRule = .addFan
        rules.allowMenQing = true
        rules.allowZhongZhang = true
        return rules
    }

    /// 兼容旧别名。
    public static var beginner: GameRules { xueliuStandard }

    /// 计分规则一样（不比每分几元：汇率每桌自己定，换预设不动它）。
    public func scoresLike(_ other: GameRules) -> Bool {
        var copy = other
        copy.yuanPerPoint = yuanPerPoint
        return copy == self
    }

    /// 封顶以后这一把按几番算。
    public func cappedFan(_ fan: Int) -> Int {
        let nonNegative = max(0, fan)
        return fanCap > 0 ? min(nonNegative, fanCap) : nonNegative
    }

    /// 一把胡牌按几番计分（若为「自摸加番」且按自摸结算，番数 +1 后再按封顶算）。
    public func paidFan(_ win: WinRecord) -> Int {
        let isZimoPayment = win.isSelfDrawn && !(win.context.gangShangHua && dianGangHuaRule == .asDianPao && win.context.dianGangDiscarder != nil)
        let raw = win.totalFan + ((isZimoPayment && zimoRule == .addFan) ? 1 : 0)
        return cappedFan(raw)
    }

    /// 一把胡牌单家应付的倍数（含自摸加底或自摸加番）。
    public func winMultiplier(_ win: WinRecord) -> Int {
        let isZimoPayment = win.isSelfDrawn && !(win.context.gangShangHua && dianGangHuaRule == .asDianPao && win.context.dianGangDiscarder != nil)
        return Payment.multiplier(totalFan: win.totalFan, isSelfDrawn: isZimoPayment, rules: self)
    }

    public func paidMultiplier(_ win: WinRecord) -> Int {
        winMultiplier(win)
    }

    enum CodingKeys: String, CodingKey {
        case mode, fanCap, zimoRule, dianGangHuaRule, allowMenQing, allowZhongZhang
        case basePoints, yuanPerPoint, minimumFan, totalHands, falseWinPenalty, swapSeatsEachRound
        case includeFlowers, kiriageMangan, onlyDiscarderPays
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameRules()
        mode = try c.decodeIfPresent(SichuanMode.self, forKey: .mode) ?? d.mode
        fanCap = try c.decodeIfPresent(Int.self, forKey: .fanCap) ?? d.fanCap
        zimoRule = try c.decodeIfPresent(ZimoRule.self, forKey: .zimoRule) ?? d.zimoRule
        dianGangHuaRule = try c.decodeIfPresent(DianGangHuaRule.self, forKey: .dianGangHuaRule) ?? d.dianGangHuaRule
        allowMenQing = try c.decodeIfPresent(Bool.self, forKey: .allowMenQing) ?? d.allowMenQing
        allowZhongZhang = try c.decodeIfPresent(Bool.self, forKey: .allowZhongZhang) ?? d.allowZhongZhang
        let decodedBase = try c.decodeIfPresent(Int.self, forKey: .basePoints) ?? d.basePoints
        basePoints = max(1, decodedBase)
        yuanPerPoint = try c.decodeIfPresent(Double.self, forKey: .yuanPerPoint) ?? d.yuanPerPoint
        minimumFan = try c.decodeIfPresent(Int.self, forKey: .minimumFan) ?? d.minimumFan
        totalHands = try c.decodeIfPresent(Int.self, forKey: .totalHands) ?? d.totalHands
        falseWinPenalty = try c.decodeIfPresent(Int.self, forKey: .falseWinPenalty) ?? d.falseWinPenalty
        swapSeatsEachRound = try c.decodeIfPresent(Bool.self, forKey: .swapSeatsEachRound) ?? d.swapSeatsEachRound
        includeFlowers = try c.decodeIfPresent(Bool.self, forKey: .includeFlowers) ?? false
        kiriageMangan = try c.decodeIfPresent(Bool.self, forKey: .kiriageMangan) ?? false
        onlyDiscarderPays = try c.decodeIfPresent(Bool.self, forKey: .onlyDiscarderPays) ?? true
    }
}

/// 局内刮风（直杠 / 巴杠）与下雨（暗杠）记录。
public struct KongRecord: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// 刮风·直杠（明杠）：收点杠者 2 倍底分。
        case zhiGang
        /// 刮风·巴杠（弯杠/加杠）：收在场未胡每家 1 倍底分。
        case baGang
        /// 下雨·暗杠：收在场未胡每家 2 倍底分。
        case anGang

        public var name: String {
            switch self {
            case .zhiGang: return "刮风·直杠"
            case .baGang: return "刮风·巴杠"
            case .anGang: return "下雨·暗杠"
            }
        }

        public var shortName: String {
            switch self {
            case .zhiGang: return "直杠"
            case .baGang: return "巴杠"
            case .anGang: return "暗杠"
            }
        }
    }

    /// 开杠玩家（0–3）。
    public var player: Int
    public var kind: Kind
    /// 直杠时的点杠者（0–3）；巴杠、暗杠为 nil。
    public var discarder: Int?
    /// 杠的是哪张牌（可选）。
    public var tile: Tile?

    public init(player: Int, kind: Kind, discarder: Int? = nil, tile: Tile? = nil) {
        self.player = player
        self.kind = kind
        self.discarder = kind == .zhiGang ? discarder : nil
        self.tile = tile
    }
}

/// 流局荒庄时单名玩家的查叫状态。
public enum PlayerTingState: Hashable, Codable, Sendable {
    /// 已在本局胡牌（血战到底已胡离场，或血流成河已胡锁定），不参与退税与查叫赔付。
    case alreadyWon
    /// 花猪：万、筒、条三门俱全（退还本局所有刮风下雨杠钱，并按封顶番数赔给所有非花猪在场玩家）。
    case huaZhu
    /// 未下叫（未听牌）：退还本局所有刮风下雨杠钱，并按大叫最高番数赔给所有已下叫玩家。
    case notTing
    /// 已下叫（已听牌）：最高可能胡牌番数（大叫）为 `maxFan`，可附带拍照识别的 13 张手牌。
    case ting(maxFan: Int, hand: Hand? = nil)

    /// 是否需要退还本局收到的所有刮风下雨杠钱（未下叫或花猪均需退税）。
    public var needsTaxRefund: Bool {
        switch self {
        case .huaZhu, .notTing: return true
        case .alreadyWon, .ting: return false
        }
    }

    public var label: String {
        switch self {
        case .alreadyWon: return "已胡"
        case .huaZhu: return "花猪"
        case .notTing: return "未下叫"
        case .ting(let fan, _): return "下叫（大叫 \(fan) 番）"
        }
    }
}

/// 荒庄流局结算记录（查花猪 + 查大叫 + 自动退税）。
public struct DrawSettlementRecord: Hashable, Codable, Sendable {
    /// 四名玩家的流局状态（下标 0–3）。
    public var states: [PlayerTingState]
    /// 系统自动计算出的「流局退税」四家得失分（已包含在 `HandRecord.deltas` 中，单独存一份供账本展示退税明细）。
    public var taxRefundDeltas: [Int]
    /// 查花猪与查大叫本身的赔付得失分（不含退税）。
    public var penaltyDeltas: [Int]

    public init(
        states: [PlayerTingState],
        taxRefundDeltas: [Int] = [0, 0, 0, 0],
        penaltyDeltas: [Int] = [0, 0, 0, 0]
    ) {
        self.states = states
        self.taxRefundDeltas = taxRefundDeltas
        self.penaltyDeltas = penaltyDeltas
    }
}

/// 一条账本事件的结果（四川麻将支持一局内多次刮风下雨、多次胡牌、呼叫转移与荒庄退税查叫）。
public enum HandOutcome: Hashable, Codable, Sendable {
    /// 刮风（直杠/巴杠）或下雨（暗杠），记在当前局内，不推进局数。
    case kong(KongRecord)
    /// 胡牌（血战到底第 3 家胡牌时自动推进局数；第 1、2 家胡牌或血流成河胡牌留在当前局）。
    case win(WinRecord)
    /// 荒庄流局查叫结算（查花猪 + 查大叫 + 自动退税），结束当前局并推进局数。
    case drawSettlement(DrawSettlementRecord)
    /// 普通荒庄流局（无赔付无退税），结束当前局并推进局数。
    case drawn
    /// 诈胡（错和）：赔在场其他玩家罚分，不推进局数。
    case falseWin(offender: Int)
    /// 手动记分，四个数加起来为 0。
    case manual(deltas: [Int], note: String)

    /// 该事件是否固定推进局数（注：血战到底满 3 人胡牌时也会推进局数，由状态机 `reflow` 判定）。
    public var advancesHand: Bool {
        switch self {
        case .drawSettlement, .drawn:
            return true
        case .win(let win):
            return win.endsRound
        case .kong, .falseWin, .manual:
            return false
        }
    }
}

public struct WinRecord: Hashable, Codable, Sendable {
    /// 胡牌者（玩家下标，0–3）。
    public var winner: Int
    /// 点炮者；nil 为自摸。
    public var discarder: Int?
    /// 确认后的手牌；手动输入番数时可以为空。
    public var hand: Hand?
    public var context: WinContext
    public var fans: [FanEntry]
    /// 整手牌中「根」的总数。
    public var genCount: Int
    /// 兼容字段（恒为 0）。
    public var flowerFan: Int
    /// 兼容字段。
    public var fu: Int
    /// 事后在账本里直接改了番数。有它时 `fans` 不再可信，界面清空明细，改局时也不重新算番。
    public var fanOverride: Int?
    /// 杠上炮「呼叫转移」转给胡牌者的杠钱分数（由状态机自动从点炮者上一笔杠算出，也可指定）。
    public var callTransferAmount: Int
    /// 本局内第几次胡牌（血战到底：1=一胡，2=二胡，3=三胡；血流成河：第 N 胡）。
    public var winOrder: Int
    /// 这笔胡牌是否结束了当前局（血战到底三胡时为 true）。
    public var endsRound: Bool

    public init(
        winner: Int,
        discarder: Int?,
        hand: Hand?,
        context: WinContext,
        fans: [FanEntry],
        flowerFan: Int = 0,
        fu: Int = 0,
        fanOverride: Int? = nil,
        genCount: Int? = nil,
        callTransferAmount: Int = 0,
        winOrder: Int = 1,
        endsRound: Bool = false
    ) {
        self.winner = winner
        self.discarder = discarder
        self.hand = hand
        self.context = context
        self.fans = fans
        self.genCount = genCount ?? hand?.genCount ?? 0
        self.flowerFan = flowerFan
        self.fu = fu
        self.fanOverride = fanOverride
        self.callTransferAmount = callTransferAmount
        self.winOrder = winOrder
        self.endsRound = endsRound
    }

    public init(winner: Int, discarder: Int?, hand: Hand, context: WinContext, result: ScoringResult, callTransferAmount: Int = 0) {
        self.init(
            winner: winner,
            discarder: discarder,
            hand: hand,
            context: context,
            fans: result.fans,
            flowerFan: result.flowerFan,
            fu: result.fu,
            genCount: result.genCount,
            callTransferAmount: callTransferAmount
        )
    }

    enum CodingKeys: String, CodingKey {
        case winner, discarder, hand, context, fans, genCount, flowerFan, fu, fanOverride
        case callTransferAmount, winOrder, endsRound
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        winner = try c.decode(Int.self, forKey: .winner)
        discarder = try c.decodeIfPresent(Int.self, forKey: .discarder)
        let decodedHand = try c.decodeIfPresent(Hand.self, forKey: .hand)
        hand = decodedHand
        context = try c.decode(WinContext.self, forKey: .context)
        fans = try c.decode([FanEntry].self, forKey: .fans)
        genCount = try c.decodeIfPresent(Int.self, forKey: .genCount) ?? decodedHand?.genCount ?? 0
        flowerFan = try c.decodeIfPresent(Int.self, forKey: .flowerFan) ?? 0
        fu = try c.decodeIfPresent(Int.self, forKey: .fu) ?? 0
        fanOverride = try c.decodeIfPresent(Int.self, forKey: .fanOverride)
        callTransferAmount = try c.decodeIfPresent(Int.self, forKey: .callTransferAmount) ?? 0
        winOrder = try c.decodeIfPresent(Int.self, forKey: .winOrder) ?? 1
        endsRound = try c.decodeIfPresent(Bool.self, forKey: .endsRound) ?? false
    }

    public var totalFan: Int { fanOverride ?? (fans.reduce(0) { $0 + $1.points } + flowerFan) }
    public var isSelfDrawn: Bool { discarder == nil }
}

public struct HandRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// 第几局（0 起），同一局内的刮风、下雨、先后胡牌、荒庄查叫共享同一个 `handIndex`。
    public var handIndex: Int
    public var outcome: HandOutcome
    /// 四个玩家在这一事件中的得失分，下标同 `Game.players`。
    public var deltas: [Int]
    public var date: Date

    public init(id: UUID = UUID(), handIndex: Int, outcome: HandOutcome, deltas: [Int], date: Date = Date()) {
        self.id = id
        self.handIndex = handIndex
        self.outcome = outcome
        self.deltas = deltas
        self.date = date
    }
}

public enum GameError: Error, Hashable, Sendable {
    case finished
    case invalidPlayer
    case discarderIsWinner
    case playerAlreadyWonInRound(String)
    case belowMinimumFan(Int)
    case deltasMustSumToZero
    case recordNotFound
    case tooManyHands(Int)

    public var message: String {
        switch self {
        case .finished: return "这场牌局已经打完了"
        case .invalidPlayer: return "玩家不对"
        case .discarderIsWinner: return "点炮（或点杠）的人不能是自己"
        case .playerAlreadyWonInRound(let name): return "\(name)在本局已经胡牌离场了（血战到底）"
        case .belowMinimumFan(let fan): return "只有 \(fan) 番，不够本场起胡番数"
        case .deltasMustSumToZero: return "四个人的得失分加起来要等于 0"
        case .recordNotFound: return "找不到这一条记录"
        case .tooManyHands(let total): return "这样改就超过 \(total) 局了"
        }
    }
}

/// 本局内的一笔刮风下雨流水（用于杠上炮「呼叫转移」与荒庄未下叫「自动退税」）。
public struct RoundKongEntry: Hashable, Sendable {
    public let recordID: UUID
    public let kong: KongRecord
    /// 当时这笔杠的四家收付明细（如暗杠 `[+6, -2, -2, -2]`）。
    public let deltas: [Int]
    /// 是否已经因「杠上炮 · 呼叫转移」转移给了胡牌者（已转移的杠钱不再重复退税）。
    public var isTransferred: Bool = false

    public var gain: Int { deltas[kong.player] }
}

/// 当前正在进行的这一局的实时状态机快照。
public struct LiveRoundState: Hashable, Sendable {
    /// 当前是第几局（0 起）。
    public var handIndex: Int = 0
    /// 当前仍在场未胡的玩家下标（血战到底中有人胡牌即移出；血流成河中始终为 4 人）。
    public var activePlayers: [Int] = [0, 1, 2, 3]
    /// 本局已胡牌的玩家下标（按先后胡牌顺序，如 `[0, 2]` 表示 0 号一胡、2 号二胡）。
    public var wonPlayers: [Int] = []
    /// 本局内已发生的所有刮风下雨记录。
    public var kongs: [RoundKongEntry] = []
    /// 本局内四家的累计得失分。
    public var roundDeltas: [Int] = [0, 0, 0, 0]
    /// 本局内已发生的所有事件记录。
    public var events: [HandRecord] = []

    public init(handIndex: Int = 0) {
        self.handIndex = handIndex
    }

    /// 某玩家在本局通过刮风下雨净收到的杠钱总额（未呼叫转移的部分，若流局未下叫需全额退税）。
    public func refundableKongGain(for player: Int) -> Int {
        kongs.filter { $0.kong.player == player && !$0.isTransferred }
            .reduce(0) { $0 + $1.gain }
    }

    /// 血战到底中某玩家是第几个胡的（1=一胡，2=二胡，3=三胡；未胡返回 nil）。
    public func xuezhanWinOrder(of player: Int) -> Int? {
        guard let idx = wonPlayers.firstIndex(of: player) else { return nil }
        return idx + 1
    }

    /// 血流成河中某玩家本局已经胡了几次。
    public func winCount(of player: Int) -> Int {
        wonPlayers.filter { $0 == player }.count
    }
}

/// 一场四川麻将牌局：四个人、家规、以及按时间顺序记录的局内事件流。
public struct Game: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    /// 开局时的座位：下标 0 东、1 南、2 西、3 北。东家是第一局的庄。
    public var players: [Player]
    /// 用这台手机的人是 `players` 里的第几个（牌桌图上画在最下面，首页历史显示他的输赢）。
    public var me: Int
    public var rules: GameRules
    public private(set) var records: [HandRecord]

    public init(id: UUID = UUID(), players: [Player], me: Int = 0, rules: GameRules = GameRules(), startedAt: Date = Date()) {
        precondition(players.count == 4, "四川麻将固定 4 人")
        precondition((0..<4).contains(me), "我必须是四个人之一")
        self.id = id
        self.players = players
        self.me = me
        self.rules = rules
        self.records = []
        self.startedAt = startedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, players, me, rules, records
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        players = try c.decode([Player].self, forKey: .players)
        let me = try c.decodeIfPresent(Int.self, forKey: .me) ?? 0
        self.me = (0..<4).contains(me) ? me : 0
        rules = try c.decodeIfPresent(GameRules.self, forKey: .rules) ?? GameRules()
        records = try c.decodeIfPresent([HandRecord].self, forKey: .records) ?? []
        try? reflow(edited: nil)
    }

    // MARK: 局内状态机与局数

    /// 当前正在进行的这一局的实时状态（包含在场未胡玩家、本局刮风下雨流水、已胡玩家等）。
    public var liveRound: LiveRoundState {
        computeLiveState(through: records.count)
    }

    /// 某一条记录发生之前的局内状态（用于编辑或详情展示）。
    public func roundState(beforeRecord id: UUID) -> LiveRoundState {
        let idx = records.firstIndex { $0.id == id } ?? records.count
        return computeLiveState(through: idx)
    }

    /// 已经打完的局数，也就是当前正在打第几局（0 起）。
    public var currentHandIndex: Int {
        liveRound.handIndex
    }

    /// 实际已经打过的局数（若当前局里已经有过刮风下雨或胡牌记录，提前结束结算时也算 1 局）。
    public var playedHandsCount: Int {
        currentHandIndex + (liveRound.events.isEmpty ? 0 : 1)
    }

    public var isFinished: Bool { endedAt != nil || currentHandIndex >= rules.totalHands }

    public var remainingHands: Int { max(0, rules.totalHands - currentHandIndex) }

    public func roundIndex(ofHand hand: Int) -> Int { min(hand / 4, 3) }

    public func prevalentWind(ofHand hand: Int) -> Wind { Wind(rawValue: roundIndex(ofHand: hand))! }

    public var prevalentWind: Wind { prevalentWind(ofHand: currentHandIndex) }

    public func seating(ofRound round: Int) -> [Int] {
        guard rules.swapSeatsEachRound else { return [0, 1, 2, 3] }
        let table = [[0, 1, 2, 3], [1, 0, 3, 2], [2, 3, 1, 0], [3, 2, 0, 1]]
        return table[min(max(round, 0), 3)]
    }

    public var currentSeating: [Int] {
        seating(ofRound: roundIndex(ofHand: currentHandIndex))
    }

    public func position(of player: Int, inHand hand: Int) -> Int {
        seating(ofRound: roundIndex(ofHand: hand)).firstIndex(of: player)!
    }

    /// 四川麻将庄家规则：
    /// - 第 1 局（hand == 0）东家坐庄；
    /// - 后续各局：上一局第一个胡牌的人（一胡）坐庄；若上一局一炮多响（前两胡均为同一人点炮）则点炮者坐庄；若上一局荒庄没人胡，则上一局庄家连庄。
    public func dealer(ofHand hand: Int) -> Int {
        var currentDealer = seating(ofRound: 0)[0]
        guard hand > 0 else { return currentDealer }
        for h in 0..<hand {
            let handWins = records.compactMap { rec -> WinRecord? in
                guard rec.handIndex == h, case .win(let w) = rec.outcome else { return nil }
                return w
            }
            if let first = handWins.first {
                if handWins.count >= 2,
                   let d1 = first.discarder,
                   handWins[1].discarder == d1 {
                    currentDealer = d1
                } else {
                    currentDealer = first.winner
                }
            }
        }
        return currentDealer
    }

    public var dealer: Int { dealer(ofHand: currentHandIndex) }

    public func seatWind(of player: Int, inHand hand: Int) -> Wind {
        let d = dealer(ofHand: hand)
        let offset = (position(of: player, inHand: hand) - position(of: d, inHand: hand) + 4) % 4
        return Wind(rawValue: offset)!
    }

    public func seatWind(of player: Int) -> Wind { seatWind(of: player, inHand: currentHandIndex) }

    /// 当前局某个玩家胡牌时的默认 WinContext（自动带上桌规的门清、中张设置，以及若刚发生过直杠则带上点杠者）。
    public func winContext(for winner: Int) -> WinContext {
        let state = liveRound
        let lastZhiGangDiscarder = state.kongs.last(where: { $0.kong.player == winner && $0.kong.kind == .zhiGang })?.kong.discarder
        return WinContext(
            prevalentWind: prevalentWind,
            seatWind: seatWind(of: winner),
            allowMenQing: rules.allowMenQing,
            allowZhongZhang: rules.allowZhongZhang,
            selfDrawnAddFan: false,
            dianGangDiscarder: lastZhiGangDiscarder
        )
    }

    // MARK: 分数

    /// 每个人的累计净得失分（四家之和恒为 0）。
    public var scores: [Int] {
        records.reduce(into: [0, 0, 0, 0]) { total, record in
            for i in 0..<4 { total[i] += record.deltas[i] }
        }
    }

    /// 分数折合多少元（按 `yuanPerPoint` = 每 1 分几元计算）。
    public func money(forPoints points: Int) -> Double {
        Double(points) * rules.yuanPerPoint
    }

    /// 本场最大的一手胡牌。
    public var biggestWin: (record: HandRecord, win: WinRecord)? {
        records.compactMap { record -> (HandRecord, WinRecord)? in
            if case .win(let win) = record.outcome { return (record, win) }
            return nil
        }
        .max { ($0.0.deltas[$0.1.winner], $0.1.totalFan) < ($1.0.deltas[$1.1.winner], $1.1.totalFan) }
    }

    // MARK: 记账操作（刮风下雨、胡牌、流局查叫退税、手动改分）

    /// 记录一笔刮风（直杠 / 巴杠）或下雨（暗杠）。
    @discardableResult
    public mutating func recordKong(_ kong: KongRecord) throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        var copy = self
        copy.records.append(HandRecord(handIndex: currentHandIndex, outcome: .kong(kong), deltas: [0, 0, 0, 0]))
        let newID = copy.records.last!.id
        try copy.reflow(edited: newID)
        self = copy
        return records.last!
    }

    /// 记录一手胡牌（支持血战到底先后胡牌、血流成河连胡、杠上炮自动呼叫转移）。
    @discardableResult
    public mutating func recordWin(_ win: WinRecord) throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        var copy = self
        copy.records.append(HandRecord(handIndex: currentHandIndex, outcome: .win(win), deltas: [0, 0, 0, 0]))
        let newID = copy.records.last!.id
        try copy.reflow(edited: newID)
        self = copy
        return records.last!
    }

    /// 记录荒庄流局查叫（自动执行未下叫/花猪「退税」+ 查花猪封顶赔付 + 查大叫最高番赔付），并结束当前局。
    @discardableResult
    public mutating func recordDrawSettlement(states: [PlayerTingState]) throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        guard states.count == 4 else { throw GameError.invalidPlayer }
        var copy = self
        let settlement = DrawSettlementRecord(states: states)
        copy.records.append(HandRecord(handIndex: currentHandIndex, outcome: .drawSettlement(settlement), deltas: [0, 0, 0, 0]))
        let newID = copy.records.last!.id
        try copy.reflow(edited: newID)
        self = copy
        return records.last!
    }

    /// 记录普通流局（或直接结束当前局进入下一局）。
    @discardableResult
    public mutating func recordDraw() throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        var copy = self
        copy.records.append(HandRecord(handIndex: currentHandIndex, outcome: .drawn, deltas: [0, 0, 0, 0]))
        let newID = copy.records.last!.id
        try copy.reflow(edited: newID)
        self = copy
        return records.last!
    }

    @discardableResult
    public mutating func recordFalseWin(offender: Int) throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        var copy = self
        copy.records.append(HandRecord(handIndex: currentHandIndex, outcome: .falseWin(offender: offender), deltas: [0, 0, 0, 0]))
        let newID = copy.records.last!.id
        try copy.reflow(edited: newID)
        self = copy
        return records.last!
    }

    @discardableResult
    public mutating func recordManual(deltas: [Int], note: String = "") throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        var copy = self
        copy.records.append(HandRecord(handIndex: currentHandIndex, outcome: .manual(deltas: deltas, note: note), deltas: deltas))
        let newID = copy.records.last!.id
        try copy.reflow(edited: newID)
        self = copy
        return records.last!
    }

    /// 撤销最后一条记录。
    @discardableResult
    public mutating func undoLast() -> HandRecord? {
        guard !records.isEmpty else { return nil }
        endedAt = nil
        let removed = records.removeLast()
        try? reflow(edited: nil)
        return removed
    }

    public mutating func end(at date: Date = Date()) {
        endedAt = date
    }

    // MARK: 改以前的记录与改家规

    public mutating func replace(_ id: UUID, with outcome: HandOutcome) throws {
        self = try replacing(id, with: outcome)
    }

    public func replacing(_ id: UUID, with outcome: HandOutcome) throws -> Game {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw GameError.recordNotFound }
        var copy = self
        copy.records[index].outcome = outcome
        try copy.reflow(edited: id)
        return copy
    }

    public mutating func changeRules(_ newRules: GameRules) throws {
        self = try changingRules(newRules)
    }

    public func changingRules(_ newRules: GameRules) throws -> Game {
        var copy = self
        copy.rules = newRules
        try copy.reflow(edited: nil)
        return copy
    }

    public var winsBelowMinimum: [HandRecord] {
        records.filter { record in
            guard case .win(let win) = record.outcome else { return false }
            return win.totalFan < rules.minimumFan
        }
    }

    public mutating func remove(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records.remove(at: index)
        try? reflow(edited: nil)
    }

    // MARK: 局内多事件状态机重算（Reflow）

    private func computeLiveState(through limit: Int) -> LiveRoundState {
        var state = LiveRoundState(handIndex: 0)
        let upper = min(limit, records.count)
        for i in 0..<upper {
            let record = records[i]
            switch record.outcome {
            case .kong(let kong):
                state.kongs.append(RoundKongEntry(recordID: record.id, kong: kong, deltas: record.deltas))
                for p in 0..<4 { state.roundDeltas[p] += record.deltas[p] }
                state.events.append(record)
            case .win(let win):
                if !win.isSelfDrawn, let discarder = win.discarder, win.context.gangShangPao,
                   let kIdx = state.kongs.lastIndex(where: { $0.kong.player == discarder && !$0.isTransferred }) {
                    state.kongs[kIdx].isTransferred = true
                }
                for p in 0..<4 { state.roundDeltas[p] += record.deltas[p] }
                state.events.append(record)
                state.wonPlayers.append(win.winner)
                if rules.mode == .xuezhan {
                    state.activePlayers.removeAll { $0 == win.winner }
                }
                if win.endsRound || (rules.mode == .xuezhan && state.activePlayers.count <= 1) {
                    state = LiveRoundState(handIndex: state.handIndex + 1)
                }
            case .drawSettlement, .drawn:
                state = LiveRoundState(handIndex: state.handIndex + 1)
            case .falseWin, .manual:
                for p in 0..<4 { state.roundDeltas[p] += record.deltas[p] }
                state.events.append(record)
            }
        }
        return state
    }

    private mutating func reflow(edited: UUID?) throws {
        var state = LiveRoundState(handIndex: 0)

        for i in records.indices {
            let isEdited = records[i].id == edited
            records[i].handIndex = state.handIndex

            switch records[i].outcome {
            case .kong(let kong):
                if isEdited { try validateKong(kong, state: state) }
                let d = Payment.kongDeltas(kong: kong, activePlayers: state.activePlayers, rules: rules)
                records[i].deltas = d
                state.kongs.append(RoundKongEntry(recordID: records[i].id, kong: kong, deltas: d))
                for p in 0..<4 { state.roundDeltas[p] += d[p] }
                state.events.append(records[i])

            case .win(let rawWin):
                var win = reconciled(rawWin, inHand: state.handIndex, state: state, edited: isEdited)
                if isEdited { try validateWin(win, state: state) }

                // 杠上炮 · 呼叫转移：自动将点炮者在本局最近一笔未转移的杠钱转给胡牌者
                if !win.isSelfDrawn, let discarder = win.discarder, win.context.gangShangPao {
                    if let kIdx = state.kongs.lastIndex(where: { $0.kong.player == discarder && !$0.isTransferred }) {
                        win.callTransferAmount = state.kongs[kIdx].gain
                        state.kongs[kIdx].isTransferred = true
                    } else if win.callTransferAmount == 0 {
                        // 若未单独记杠直接勾了杠上炮，默认按直杠/暗杠 2 倍底分呼叫转移
                        win.callTransferAmount = 2 * max(1, rules.basePoints)
                    }
                } else {
                    win.callTransferAmount = 0
                }

                win.winOrder = state.wonPlayers.count + 1
                let nextActiveCount = rules.mode == .xuezhan
                    ? state.activePlayers.filter { $0 != win.winner }.count
                    : state.activePlayers.count
                win.endsRound = (rules.mode == .xuezhan && nextActiveCount <= 1)

                let d = Payment.winDeltas(
                    win: win,
                    activePlayers: state.activePlayers,
                    dealer: dealer(ofHand: state.handIndex),
                    rules: rules
                )
                records[i].outcome = .win(win)
                records[i].deltas = d

                for p in 0..<4 { state.roundDeltas[p] += d[p] }
                state.events.append(records[i])
                state.wonPlayers.append(win.winner)
                if rules.mode == .xuezhan {
                    state.activePlayers.removeAll { $0 == win.winner }
                }
                if win.endsRound {
                    state = LiveRoundState(handIndex: state.handIndex + 1)
                }

            case .drawSettlement(var settlement):
                guard settlement.states.count == 4 else { throw GameError.invalidPlayer }
                // 已经胡牌的玩家固定标记为 .alreadyWon，不退税
                for won in state.wonPlayers where (0..<4).contains(won) {
                    settlement.states[won] = .alreadyWon
                }
                let computed = Payment.drawSettlementDeltas(
                    states: settlement.states,
                    activePlayers: state.activePlayers,
                    kongs: state.kongs,
                    rules: rules
                )
                settlement.taxRefundDeltas = computed.taxRefundDeltas
                settlement.penaltyDeltas = computed.penaltyDeltas
                records[i].outcome = .drawSettlement(settlement)
                records[i].deltas = computed.totalDeltas
                state = LiveRoundState(handIndex: state.handIndex + 1)

            case .drawn:
                records[i].deltas = [0, 0, 0, 0]
                state = LiveRoundState(handIndex: state.handIndex + 1)

            case .falseWin(let offender):
                guard (0..<4).contains(offender) else { throw GameError.invalidPlayer }
                let d = Payment.falseWinDeltas(offender: offender, activePlayers: state.activePlayers, penalty: rules.falseWinPenalty)
                records[i].deltas = d
                for p in 0..<4 { state.roundDeltas[p] += d[p] }
                state.events.append(records[i])

            case .manual(let deltas, _):
                guard deltas.count == 4, deltas.reduce(0, +) == 0 else { throw GameError.deltasMustSumToZero }
                records[i].deltas = deltas
                for p in 0..<4 { state.roundDeltas[p] += deltas[p] }
                state.events.append(records[i])
            }
        }

        guard state.handIndex <= rules.totalHands else { throw GameError.tooManyHands(rules.totalHands) }
    }

    private func reconciled(_ win: WinRecord, inHand hand: Int, state: LiveRoundState, edited: Bool) -> WinRecord {
        var context = win.context
        context.prevalentWind = prevalentWind(ofHand: hand)
        context.seatWind = seatWind(of: win.winner, inHand: hand)
        context.selfDrawn = win.isSelfDrawn
        context.allowMenQing = rules.allowMenQing
        context.allowZhongZhang = rules.allowZhongZhang
        context.selfDrawnAddFan = false

        if context.selfDrawn {
            context.gangShangPao = false
            context.qiangGangHu = false
            if context.dianGangDiscarder == nil {
                context.dianGangDiscarder = state.kongs.last(where: { $0.kong.player == win.winner && $0.kong.kind == .zhiGang })?.kong.discarder
            }
        } else {
            context.tianHu = false
            if rules.dianGangHuaRule != .asDianPao {
                context.gangShangHua = false
            }
        }

        var updated = win
        updated.context = context
        if let tiles = win.hand, win.fanOverride == nil,
           case .success(let result) = FanCalculator.score(tiles, context: context),
           edited || result.meetsMinimum(rules.minimumFan) {
            updated.fans = result.fans
            updated.genCount = result.genCount
            updated.flowerFan = 0
            updated.fu = 0
        }
        return updated
    }

    private func validateKong(_ kong: KongRecord, state: LiveRoundState) throws {
        guard (0..<4).contains(kong.player) else { throw GameError.invalidPlayer }
        if rules.mode == .xuezhan && !state.activePlayers.contains(kong.player) {
            throw GameError.playerAlreadyWonInRound(players[kong.player].name)
        }
        if kong.kind == .zhiGang {
            guard let discarder = kong.discarder, (0..<4).contains(discarder) else { throw GameError.invalidPlayer }
            guard discarder != kong.player else { throw GameError.discarderIsWinner }
            if rules.mode == .xuezhan && !state.activePlayers.contains(discarder) {
                throw GameError.playerAlreadyWonInRound(players[discarder].name)
            }
        }
    }

    private func validateWin(_ win: WinRecord, state: LiveRoundState) throws {
        guard (0..<4).contains(win.winner) else { throw GameError.invalidPlayer }
        if rules.mode == .xuezhan && !state.activePlayers.contains(win.winner) {
            throw GameError.playerAlreadyWonInRound(players[win.winner].name)
        }
        if let discarder = win.discarder {
            guard (0..<4).contains(discarder) else { throw GameError.invalidPlayer }
            guard discarder != win.winner else { throw GameError.discarderIsWinner }
            if rules.mode == .xuezhan && !state.activePlayers.contains(discarder) {
                throw GameError.playerAlreadyWonInRound(players[discarder].name)
            }
        }
        guard win.totalFan >= rules.minimumFan else { throw GameError.belowMinimumFan(win.totalFan) }
    }
}

/// 四川麻将（血战到底 / 血流成河）倍数、刮风下雨、呼叫转移与荒庄退税计算引擎。
public enum Payment {
    /// 单家应付倍数：
    /// - 点炮：$2^{\min(\text{番}, \text{封顶})}$ 倍（0 番 = 1 倍，1 番 = 2 倍，2 番 = 4 倍，3 番 = 8 倍，4 番 = 16 倍）。
    /// - 自摸（自摸加底）：$2^{\min(\text{番}, \text{封顶})} + 1$ 倍。
    /// - 自摸（自摸加番）：$2^{\min(\text{番}+1, \text{封顶})}$ 倍。
    public static func multiplier(totalFan: Int, isSelfDrawn: Bool, rules: GameRules = .standard) -> Int {
        if isSelfDrawn {
            switch rules.zimoRule {
            case .addDi:
                let capped = rules.cappedFan(totalFan)
                return (1 << min(capped, 20)) + 1
            case .addFan:
                let capped = rules.cappedFan(totalFan + 1)
                return 1 << min(capped, 20)
            }
        } else {
            let capped = rules.cappedFan(totalFan)
            return 1 << min(capped, 20)
        }
    }

    /// 满封顶或高番时的称号（如「满格封顶」「极品」）。
    public static func limitName(han: Int, fu: Int = 0, kiriageMangan: Bool = false) -> String? {
        if han >= 5 { return "极品" }
        return nil
    }

    /// 刮风（直杠/巴杠）与下雨（暗杠）的四家得失分：
    /// - 直杠（明杠）：点杠者一家付 $2\times$ 底分；
    /// - 巴杠（弯杠）：当前在场未胡玩家每家付 $1\times$ 底分；
    /// - 暗杠（下雨）：当前在场未胡玩家每家付 $2\times$ 底分。
    public static func kongDeltas(
        kong: KongRecord,
        activePlayers: [Int] = [0, 1, 2, 3],
        rules: GameRules = .standard
    ) -> [Int] {
        let base = max(1, rules.basePoints)
        var deltas = [0, 0, 0, 0]
        guard (0..<4).contains(kong.player) else { return deltas }

        switch kong.kind {
        case .zhiGang:
            guard let discarder = kong.discarder, (0..<4).contains(discarder), discarder != kong.player else {
                return deltas
            }
            let pay = 2 * base
            deltas[discarder] -= pay
            deltas[kong.player] += pay
        case .baGang:
            let each = 1 * base
            for p in activePlayers where p != kong.player {
                deltas[p] -= each
                deltas[kong.player] += each
            }
        case .anGang:
            let each = 2 * base
            for p in activePlayers where p != kong.player {
                deltas[p] -= each
                deltas[kong.player] += each
            }
        }
        return deltas
    }

    /// 胡牌时的四家得失分（含血战到底在场未胡范围过滤、点杠花规则、杠上炮呼叫转移）。
    public static func winDeltas(
        win: WinRecord,
        activePlayers: [Int] = [0, 1, 2, 3],
        dealer: Int = 0,
        rules: GameRules = .standard
    ) -> [Int] {
        let base = max(1, rules.basePoints)
        var deltas = [0, 0, 0, 0]

        // 若为点杠花且家规设为「点杠花算点炮」，由点杠者一家按点炮付
        if win.isSelfDrawn,
           win.context.gangShangHua,
           rules.dianGangHuaRule == .asDianPao,
           let dianGangPayer = win.context.dianGangDiscarder,
           (0..<4).contains(dianGangPayer),
           dianGangPayer != win.winner {
            let mult = multiplier(totalFan: win.totalFan, isSelfDrawn: false, rules: rules)
            let pay = mult * base
            deltas[dianGangPayer] -= pay
            deltas[win.winner] += pay
            return deltas
        }

        if let discarder = win.discarder {
            let mult = multiplier(totalFan: win.totalFan, isSelfDrawn: false, rules: rules)
            let pay = mult * base + max(0, win.callTransferAmount)
            deltas[discarder] -= pay
            deltas[win.winner] += pay
        } else {
            let mult = multiplier(totalFan: win.totalFan, isSelfDrawn: true, rules: rules)
            let each = mult * base
            for p in activePlayers where p != win.winner {
                deltas[p] -= each
                deltas[win.winner] += each
            }
        }
        return deltas
    }

    /// 兼容旧调用签名。
    public static func winDeltas(
        winner: Int,
        discarder: Int?,
        dealer: Int = 0,
        totalFan: Int,
        fu: Int = 0,
        activePlayers: [Int] = [0, 1, 2, 3],
        rules: GameRules = .standard
    ) -> [Int] {
        let dummy = WinRecord(
            winner: winner,
            discarder: discarder,
            hand: nil,
            context: WinContext(selfDrawn: discarder == nil),
            fans: [],
            fanOverride: totalFan
        )
        return winDeltas(win: dummy, activePlayers: activePlayers, dealer: dealer, rules: rules)
    }

    /// 荒庄流局结算：
    /// 1. **自动退税**：凡是未下叫（`.notTing`）或花猪（`.huaZhu`）的玩家，在本局内收到的所有未转移刮风下雨杠钱原路退回给当时的支付者；
    /// 2. **查花猪赔付**：花猪玩家按封顶番数（无封顶时按 4 番 16 倍）赔给所有非花猪在场玩家；
    /// 3. **查大叫赔付**：未下叫玩家按已下叫玩家的「大叫（最高可能番数）」赔付。
    public static func drawSettlementDeltas(
        states: [PlayerTingState],
        activePlayers: [Int] = [0, 1, 2, 3],
        kongs: [RoundKongEntry] = [],
        rules: GameRules = .standard
    ) -> (totalDeltas: [Int], taxRefundDeltas: [Int], penaltyDeltas: [Int]) {
        guard states.count == 4 else { return ([0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]) }
        let base = max(1, rules.basePoints)

        // 1. 流局退税：未下叫或花猪的玩家，原路退回本局所有未呼叫转移的刮风下雨所得
        var taxRefund = [0, 0, 0, 0]
        for entry in kongs where !entry.isTransferred {
            let receiver = entry.kong.player
            if (0..<4).contains(receiver), states[receiver].needsTaxRefund {
                for p in 0..<4 {
                    taxRefund[p] -= entry.deltas[p]
                }
            }
        }

        // 2. 查花猪：花猪向所有非花猪在场玩家赔封顶番
        var penalty = [0, 0, 0, 0]
        let effectiveCapFan = rules.fanCap > 0 ? rules.fanCap : 4
        let huaZhuPay = (1 << min(effectiveCapFan, 20)) * base
        let activeSet = Set(activePlayers)
        let huaZhuPlayers = (0..<4).filter { activeSet.contains($0) && states[$0] == .huaZhu }
        let nonHuaZhuActive = (0..<4).filter { activeSet.contains($0) && states[$0] != .huaZhu }

        for hz in huaZhuPlayers {
            for target in nonHuaZhuActive where target != hz {
                penalty[hz] -= huaZhuPay
                penalty[target] += huaZhuPay
            }
        }

        // 3. 查大叫：未下叫玩家（非花猪）向已下叫玩家按其大叫番数赔付
        let notTingPlayers = (0..<4).filter { activeSet.contains($0) && states[$0] == .notTing }
        for payer in notTingPlayers {
            for receiver in (0..<4) where activeSet.contains(receiver) && receiver != payer {
                if case .ting(let maxFan, _) = states[receiver] {
                    let capped = rules.cappedFan(maxFan)
                    let pay = (1 << min(capped, 20)) * base
                    penalty[payer] -= pay
                    penalty[receiver] += pay
                }
            }
        }

        let total = (0..<4).map { taxRefund[$0] + penalty[$0] }
        return (total, taxRefund, penalty)
    }

    /// 诈胡（错和）罚分：向在场其余每家赔 `penalty` 分。
    public static func falseWinDeltas(offender: Int, activePlayers: [Int] = [0, 1, 2, 3], penalty: Int) -> [Int] {
        var deltas = [0, 0, 0, 0]
        guard (0..<4).contains(offender) else { return deltas }
        for p in activePlayers where p != offender {
            deltas[p] += penalty
            deltas[offender] -= penalty
        }
        return deltas
    }
}
