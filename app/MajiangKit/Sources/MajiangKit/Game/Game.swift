import Foundation

public struct Player: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// 牌局规则。默认是立直麻将半庄规则（东南战 8 局、1 翻起和、计宝牌）；桌规不同的地方可以改。
public struct GameRules: Hashable, Codable, Sendable {
    /// 每 1000 点折合多少元（默认 1000 点 = 1 元）。
    public var yuanPerPoint: Double = 1
    /// 兼容旧字段。
    public var basePoints: Int = 0
    /// 起和翻数（立直麻将默认 1 翻起和，宝牌不计入）。
    public var minimumFan: Int = 1
    /// 是否计入宝牌（表宝牌、赤宝牌、里宝牌）。
    public var includeFlowers: Bool = true
    /// 切上满贯：30 符 4 翻、60 符 3 翻按满贯（8000 / 12000 点）算。
    public var kiriageMangan: Bool = false
    /// 每圈换座；朋友局一般不换。
    public var swapSeatsEachRound: Bool = false
    /// 错和罚符：赔另外三家各多少点（默认各 3000 点，共 9000 点）。
    public var falseWinPenalty: Int = 3000
    /// 一场几局（默认半庄战 8 局 = 东四局 + 南四局；东风战为 4 局）。
    public var totalHands: Int = 8
    /// 封顶：一把最多按几翻算（含宝牌），0 为不封顶（13 翻以上累计役满）。
    public var fanCap: Int = 0
    /// 立直麻将荣和由放铳者一家包付。
    public var onlyDiscarderPays: Bool = true

    public init() {}

    /// 标准半庄（东南战 8 局）。
    public static let standard = GameRules()

    /// 东风战（4 局快局）。
    public static var beginner: GameRules {
        var rules = GameRules()
        rules.totalHands = 4
        return rules
    }

    /// 计分规则一样（不比 1000 点几元：汇率每桌自己定，换预设不动它）。
    public func scoresLike(_ other: GameRules) -> Bool {
        var copy = other
        copy.yuanPerPoint = yuanPerPoint
        return copy == self
    }

    /// 封顶以后这一把按几翻算。
    public func cappedFan(_ fan: Int) -> Int {
        fanCap > 0 ? min(fan, fanCap) : fan
    }

    /// 一把和牌按几翻计分：不计宝牌时去掉宝牌翻数，再按封顶算。
    public func paidFan(_ win: WinRecord) -> Int {
        cappedFan(includeFlowers ? win.totalFan : win.totalFan - win.flowerFan)
    }

    enum CodingKeys: String, CodingKey {
        case yuanPerPoint, basePoints, minimumFan, includeFlowers, kiriageMangan
        case swapSeatsEachRound, falseWinPenalty, totalHands, fanCap, onlyDiscarderPays
    }

    /// 缺的字段用默认值，以后加规则不会让旧存档读不出来。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameRules()
        yuanPerPoint = try c.decodeIfPresent(Double.self, forKey: .yuanPerPoint) ?? d.yuanPerPoint
        basePoints = try c.decodeIfPresent(Int.self, forKey: .basePoints) ?? d.basePoints
        minimumFan = try c.decodeIfPresent(Int.self, forKey: .minimumFan) ?? d.minimumFan
        includeFlowers = try c.decodeIfPresent(Bool.self, forKey: .includeFlowers) ?? d.includeFlowers
        kiriageMangan = try c.decodeIfPresent(Bool.self, forKey: .kiriageMangan) ?? d.kiriageMangan
        swapSeatsEachRound = try c.decodeIfPresent(Bool.self, forKey: .swapSeatsEachRound) ?? d.swapSeatsEachRound
        falseWinPenalty = try c.decodeIfPresent(Int.self, forKey: .falseWinPenalty) ?? d.falseWinPenalty
        totalHands = try c.decodeIfPresent(Int.self, forKey: .totalHands) ?? d.totalHands
        fanCap = try c.decodeIfPresent(Int.self, forKey: .fanCap) ?? d.fanCap
        onlyDiscarderPays = try c.decodeIfPresent(Bool.self, forKey: .onlyDiscarderPays) ?? d.onlyDiscarderPays
    }
}

/// 一局的结果。
public enum HandOutcome: Hashable, Codable, Sendable {
    case win(WinRecord)
    /// 流局：不计分。
    case drawn
    /// 错和（诈和）：赔另外三家罚符，不推进局数。
    case falseWin(offender: Int)
    /// 手动记分，四个数加起来为 0。
    case manual(deltas: [Int], note: String)

    /// 这一局打完了没有（错和之后这一局继续打）。
    public var advancesHand: Bool {
        if case .falseWin = self { return false }
        return true
    }
}

public struct WinRecord: Hashable, Codable, Sendable {
    /// 和牌者（玩家下标，0–3）。
    public var winner: Int
    /// 点炮者；nil 为自摸。
    public var discarder: Int?
    /// 确认后的手牌；手动输入翻数时可以为空。
    public var hand: Hand?
    public var context: WinContext
    public var fans: [FanEntry]
    /// 宝牌翻数。
    public var flowerFan: Int
    /// 符数（默认 30 符）。
    public var fu: Int
    /// 事后在账本里直接改了翻数（含宝牌）。有它时 `fans` 不再可信，界面清空明细，改局时也不重新算翻。
    public var fanOverride: Int?

    public init(winner: Int, discarder: Int?, hand: Hand?, context: WinContext, fans: [FanEntry], flowerFan: Int,
                fu: Int = 30, fanOverride: Int? = nil) {
        self.winner = winner
        self.discarder = discarder
        self.hand = hand
        self.context = context
        self.fans = fans
        self.flowerFan = flowerFan
        self.fu = fu
        self.fanOverride = fanOverride
    }

    public init(winner: Int, discarder: Int?, hand: Hand, context: WinContext, result: ScoringResult) {
        self.init(winner: winner, discarder: discarder, hand: hand, context: context,
                  fans: result.fans, flowerFan: result.flowerFan, fu: result.fu)
    }

    enum CodingKeys: String, CodingKey {
        case winner, discarder, hand, context, fans, flowerFan, fu, fanOverride
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        winner = try c.decode(Int.self, forKey: .winner)
        discarder = try c.decodeIfPresent(Int.self, forKey: .discarder)
        hand = try c.decodeIfPresent(Hand.self, forKey: .hand)
        context = try c.decode(WinContext.self, forKey: .context)
        fans = try c.decode([FanEntry].self, forKey: .fans)
        flowerFan = try c.decodeIfPresent(Int.self, forKey: .flowerFan) ?? 0
        fu = try c.decodeIfPresent(Int.self, forKey: .fu) ?? 30
        fanOverride = try c.decodeIfPresent(Int.self, forKey: .fanOverride)
    }

    public var totalFan: Int { fanOverride ?? fans.reduce(0) { $0 + $1.points } + flowerFan }
    public var isSelfDrawn: Bool { discarder == nil }
}

public struct HandRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// 第几局（0 起），错和记在当前局上。
    public var handIndex: Int
    public var outcome: HandOutcome
    /// 四个玩家本局的得失点数，下标同 `Game.players`。
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
    case belowMinimumFan(Int)
    case deltasMustSumToZero
    case recordNotFound
    case tooManyHands(Int)

    public var message: String {
        switch self {
        case .finished: return "这场牌局已经打完了"
        case .invalidPlayer: return "玩家不对"
        case .discarderIsWinner: return "点炮的人不能是和牌的人"
        case .belowMinimumFan(let fan):
            return fan == 0 ? "无役，不能和牌（宝牌不算起和役）" : "只有 \(fan) 翻役，不够起和"
        case .deltasMustSumToZero: return "四个人的得失点加起来要等于 0"
        case .recordNotFound: return "找不到这一局"
        case .tooManyHands(let total): return "这样改就超过 \(total) 局了"
        }
    }
}

/// 一场牌局：四个人、规则、每一局的记录。场风、自风、庄家都从局数推出来，不用存。
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
        precondition(players.count == 4, "立直麻将固定 4 人")
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
    }

    // MARK: 局数、场风、自风

    /// 已经打完的局数，也就是当前是第几局（0 起）。
    public var currentHandIndex: Int { records.filter(\.outcome.advancesHand).count }

    public var isFinished: Bool { endedAt != nil || currentHandIndex >= rules.totalHands }

    public var remainingHands: Int { max(0, rules.totalHands - currentHandIndex) }

    /// 第几圈（0 东场、1 南场……），超过 4 圈按北场算。
    public func roundIndex(ofHand hand: Int) -> Int { min(hand / 4, 3) }

    public func prevalentWind(ofHand hand: Int) -> Wind { Wind(rawValue: roundIndex(ofHand: hand))! }

    public var prevalentWind: Wind { prevalentWind(ofHand: currentHandIndex) }

    /// 这一场风里，桌子东南西北四个位置上坐的是谁（玩家下标）。
    public func seating(ofRound round: Int) -> [Int] {
        guard rules.swapSeatsEachRound else { return [0, 1, 2, 3] }
        let table = [[0, 1, 2, 3], [1, 0, 3, 2], [2, 3, 1, 0], [3, 2, 0, 1]]
        return table[min(max(round, 0), 3)]
    }

    /// 某局里玩家坐在哪个位置（0 东位 … 3 北位）。
    public func position(of player: Int, inHand hand: Int) -> Int {
        seating(ofRound: roundIndex(ofHand: hand)).firstIndex(of: player)!
    }

    /// 某局的庄家（玩家下标）。
    public func dealer(ofHand hand: Int) -> Int {
        seating(ofRound: roundIndex(ofHand: hand))[hand % 4]
    }

    public var dealer: Int { dealer(ofHand: currentHandIndex) }

    /// 某局玩家的自风：庄家是东，下家是南，依此类推。
    public func seatWind(of player: Int, inHand hand: Int) -> Wind {
        let offset = (position(of: player, inHand: hand) - hand % 4 + 4) % 4
        return Wind(rawValue: offset)!
    }

    public func seatWind(of player: Int) -> Wind { seatWind(of: player, inHand: currentHandIndex) }

    /// 当前局某个玩家和牌时的 WinContext（场风、自风已经填好）。
    public func winContext(for winner: Int) -> WinContext {
        WinContext(prevalentWind: prevalentWind, seatWind: seatWind(of: winner))
    }

    // MARK: 分数

    /// 每个人的累计净得失点（四家之和恒为 0）。
    public var scores: [Int] {
        records.reduce(into: [0, 0, 0, 0]) { total, record in
            for i in 0..<4 { total[i] += record.deltas[i] }
        }
    }

    /// 点数折合多少元（按 `yuanPerPoint` = 每 1000 点几元计算）。
    public func money(forPoints points: Int) -> Double {
        (Double(points) / 1000.0) * rules.yuanPerPoint
    }

    /// 本场最大的一手和牌。
    public var biggestWin: (record: HandRecord, win: WinRecord)? {
        records.compactMap { record -> (HandRecord, WinRecord)? in
            if case .win(let win) = record.outcome { return (record, win) }
            return nil
        }
        .max { ($0.0.deltas[$0.1.winner], $0.1.totalFan) < ($1.0.deltas[$1.1.winner], $1.1.totalFan) }
    }

    // MARK: 记分

    @discardableResult
    public mutating func recordWin(_ win: WinRecord) throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        try validate(.win(win))
        let handIdx = currentHandIndex
        return append(.win(win), deltas: deltas(for: .win(win), inHand: handIdx))
    }

    @discardableResult
    public mutating func recordDraw() throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        return append(.drawn, deltas: [0, 0, 0, 0])
    }

    @discardableResult
    public mutating func recordFalseWin(offender: Int) throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        try validate(.falseWin(offender: offender))
        let handIdx = currentHandIndex
        return append(.falseWin(offender: offender), deltas: deltas(for: .falseWin(offender: offender), inHand: handIdx))
    }

    @discardableResult
    public mutating func recordManual(deltas: [Int], note: String = "") throws -> HandRecord {
        guard !isFinished else { throw GameError.finished }
        try validate(.manual(deltas: deltas, note: note))
        return append(.manual(deltas: deltas, note: note), deltas: deltas)
    }

    /// 撤销最后一条记录。
    @discardableResult
    public mutating func undoLast() -> HandRecord? {
        guard !records.isEmpty else { return nil }
        endedAt = nil
        return records.removeLast()
    }

    public mutating func end(at date: Date = Date()) {
        endedAt = date
    }

    // MARK: 改以前的局

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

    /// 按现在的起和翻数，役翻不够的和牌（中途调高了起和翻数时会有）。
    public var winsBelowMinimum: [HandRecord] {
        records.filter { record in
            guard case .win(let win) = record.outcome else { return false }
            return win.totalFan - win.flowerFan < rules.minimumFan
        }
    }

    /// 删掉某一局，后面的跟着重算。
    public mutating func remove(_ id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records.remove(at: index)
        try? reflow(edited: nil)
    }

    private mutating func reflow(edited: UUID?) throws {
        var hand = 0
        for i in records.indices {
            records[i].handIndex = hand
            let isEdited = records[i].id == edited
            if case .win(let win) = records[i].outcome {
                records[i].outcome = .win(reconciled(win, inHand: hand, edited: isEdited))
            }
            if isEdited { try validate(records[i].outcome) }
            records[i].deltas = deltas(for: records[i].outcome, inHand: hand)
            if records[i].outcome.advancesHand { hand += 1 }
        }
        guard hand <= rules.totalHands else { throw GameError.tooManyHands(rules.totalHands) }
    }

    private func reconciled(_ win: WinRecord, inHand hand: Int, edited: Bool) -> WinRecord {
        var context = win.context
        context.prevalentWind = prevalentWind(ofHand: hand)
        context.seatWind = seatWind(of: win.winner, inHand: hand)
        context.selfDrawn = win.isSelfDrawn
        if context.selfDrawn != win.context.selfDrawn {
            context.kongInvolved = false
            context.lastTileOfWall = false
        }
        guard edited || context != win.context else { return win }

        var updated = win
        updated.context = context
        if let tiles = win.hand, win.fanOverride == nil,
           case .success(let result) = FanCalculator.score(tiles, context: context),
           edited || result.meetsMinimum(rules.minimumFan) {
            updated.fans = result.fans
            updated.flowerFan = result.flowerFan
            updated.fu = result.fu
        }
        return updated
    }

    private func validate(_ outcome: HandOutcome) throws {
        switch outcome {
        case .win(let win):
            guard (0..<4).contains(win.winner) else { throw GameError.invalidPlayer }
            if let discarder = win.discarder {
                guard (0..<4).contains(discarder) else { throw GameError.invalidPlayer }
                guard discarder != win.winner else { throw GameError.discarderIsWinner }
            }
            let fanWithoutFlowers = win.totalFan - win.flowerFan
            guard fanWithoutFlowers >= rules.minimumFan else { throw GameError.belowMinimumFan(fanWithoutFlowers) }
        case .drawn:
            break
        case .falseWin(let offender):
            guard (0..<4).contains(offender) else { throw GameError.invalidPlayer }
        case .manual(let deltas, _):
            guard deltas.count == 4, deltas.reduce(0, +) == 0 else { throw GameError.deltasMustSumToZero }
        }
    }

    private func deltas(for outcome: HandOutcome, inHand handIndex: Int) -> [Int] {
        switch outcome {
        case .win(let win):
            return Payment.winDeltas(
                winner: win.winner,
                discarder: win.discarder,
                dealer: dealer(ofHand: handIndex),
                totalFan: rules.paidFan(win),
                fu: win.fu,
                rules: rules
            )
        case .drawn:
            return [0, 0, 0, 0]
        case .falseWin(let offender):
            return Payment.falseWinDeltas(offender: offender, penalty: rules.falseWinPenalty)
        case .manual(let deltas, _):
            return deltas
        }
    }

    private mutating func append(_ outcome: HandOutcome, deltas: [Int]) -> HandRecord {
        let record = HandRecord(handIndex: currentHandIndex, outcome: outcome, deltas: deltas)
        records.append(record)
        return record
    }
}

/// 立直麻将点数与收付计算。
public enum Payment {
    /// 按百位向上进位（如 `1920 -> 2000`，`3840 -> 3900`）。
    public static func ceil100(_ value: Int) -> Int {
        guard value > 0 else { return 0 }
        return ((value + 99) / 100) * 100
    }

    /// 基本点（$B = \text{符} \times 2^{\text{翻}+2}$，满贯封顶 2000，6 翻起跳满/倍满/三倍满/役满）。
    public static func basePoints(han: Int, fu: Int = 30, kiriageMangan: Bool = false) -> Int {
        guard han > 0 else { return 0 }
        if han >= 26 { return 16000 }
        if han >= 13 { return 8000 }
        if han >= 11 { return 6000 }
        if han >= 8 { return 4000 }
        if han >= 6 { return 3000 }
        if han == 5 || (han == 4 && fu >= 40) || (han == 3 && fu >= 70) {
            return 2000
        }
        if kiriageMangan && ((han == 4 && fu == 30) || (han == 3 && fu == 60)) {
            return 2000
        }
        return min(2000, fu * (1 << (han + 2)))
    }

    /// 满贯及以上的段位名称（未达满贯返回 nil）。
    public static func limitName(han: Int, fu: Int = 30, kiriageMangan: Bool = false) -> String? {
        if han >= 26 { return "双倍役满" }
        if han >= 13 { return "役满" }
        if han >= 11 { return "三倍满" }
        if han >= 8 { return "倍满" }
        if han >= 6 { return "跳满" }
        if basePoints(han: han, fu: fu, kiriageMangan: kiriageMangan) == 2000 { return "满贯" }
        return nil
    }

    /// 立直麻将一局和牌的四家得失点数：
    /// - 荣和（点炮）：放铳者一家付（庄家和 $6B$ 进百，闲家和 $4B$ 进百）。
    /// - 自摸：庄家自摸三家各付 $2B$ 进百；闲家自摸庄家付 $2B$ 进百、另外两家闲家各付 $1B$ 进百。
    public static func winDeltas(
        winner: Int,
        discarder: Int?,
        dealer: Int = 0,
        totalFan: Int,
        fu: Int = 30,
        rules: GameRules = .standard
    ) -> [Int] {
        let han = rules.cappedFan(totalFan)
        let base = basePoints(han: han, fu: fu, kiriageMangan: rules.kiriageMangan)
        var deltas = [0, 0, 0, 0]
        guard base > 0 else { return deltas }

        if let discarder {
            let pay = ceil100(base * (winner == dealer ? 6 : 4))
            deltas[discarder] -= pay
            deltas[winner] += pay
        } else if winner == dealer {
            let each = ceil100(base * 2)
            for p in 0..<4 where p != winner {
                deltas[p] -= each
                deltas[winner] += each
            }
        } else {
            let dealerPay = ceil100(base * 2)
            let childPay = ceil100(base)
            for p in 0..<4 where p != winner {
                let pay = (p == dealer) ? dealerPay : childPay
                deltas[p] -= pay
                deltas[winner] += pay
            }
        }
        return deltas
    }

    /// 错和罚符：赔另外三家各 `penalty` 点。
    public static func falseWinDeltas(offender: Int, penalty: Int) -> [Int] {
        (0..<4).map { $0 == offender ? -3 * penalty : penalty }
    }
}
