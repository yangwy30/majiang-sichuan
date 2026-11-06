import XCTest
@testable import MajiangKit

final class GameTests: XCTestCase {
    private func makeGame(mode: SichuanMode = .xuezhan, fanCap: Int = 4, zimo: ZimoRule = .addDi) -> Game {
        var rules = GameRules()
        rules.mode = mode
        rules.fanCap = fanCap
        rules.zimoRule = zimo
        rules.basePoints = 1
        rules.yuanPerPoint = 1
        return Game(players: ["杨", "小周", "阿乐", "老王"].map { Player(name: $0) }, rules: rules)
    }

    private func win(_ winner: Int, discarder: Int?, fan: Int, gangShangHua: Bool = false, gangShangPao: Bool = false, dianGangFrom: Int? = nil) -> WinRecord {
        var fans: [FanEntry] = []
        if fan > 0 {
            fans.append(FanEntry(fan: .qingYiSe, count: 1, han: fan))
        } else {
            fans.append(FanEntry(fan: .pingHu, count: 1, han: 0))
        }
        return WinRecord(
            winner: winner,
            discarder: discarder,
            hand: nil,
            context: WinContext(
                selfDrawn: discarder == nil,
                gangShangHua: gangShangHua,
                gangShangPao: gangShangPao,
                dianGangDiscarder: dianGangFrom
            ),
            fans: fans
        )
    }

    func testXuezhanOneTwoThreeWinnersAndAutoAdvanceRound() throws {
        var game = makeGame(mode: .xuezhan, fanCap: 4, zimo: .addDi)
        // 第 1 局（庄 0）：
        // 1. 玩家 0 一胡自摸 2 番（清一色 4 倍 + 自摸加底 1 = 5 分）：向在场未胡的 1、2、3 各收 5 分 -> [+15, -5, -5, -5]
        try game.recordWin(win(0, discarder: nil, fan: 2))
        XCTAssertEqual(game.scores, [15, -5, -5, -5])
        XCTAssertEqual(game.currentHandIndex, 0, "血战一胡后本局继续")
        XCTAssertEqual(game.liveRound.wonPlayers, [0])
        XCTAssertEqual(game.liveRound.activePlayers, [1, 2, 3])

        // 已胡牌玩家 0 在血战到底中不能再次胡牌
        XCTAssertThrowsError(try game.recordWin(win(0, discarder: 1, fan: 1))) { error in
            XCTAssertEqual(error as? GameError, .playerAlreadyWonInRound("杨"))
        }

        // 2. 玩家 1 二胡自摸 1 番（2 倍 + 加底 1 = 3 分）：只向未胡的 2、3 各收 3 分（玩家 0 已离场不付钱）
        try game.recordWin(win(1, discarder: nil, fan: 1))
        XCTAssertEqual(game.scores, [15, -5 + 6, -5 - 3, -5 - 3])
        XCTAssertEqual(game.currentHandIndex, 0, "血战二胡后还剩 2 人，本局继续")
        XCTAssertEqual(game.liveRound.activePlayers, [2, 3])

        // 3. 玩家 2 三胡点炮（3 放铳）3 番（8 倍 = 8 分）：3 家胡牌后本局自动结束，推进到第 2 局！
        try game.recordWin(win(2, discarder: 3, fan: 3))
        XCTAssertEqual(game.scores, [15, 1, -8 + 8, -8 - 8])
        XCTAssertEqual(game.currentHandIndex, 1, "血战 3 家胡牌后自动结束本局进入下一局")
        XCTAssertTrue(game.liveRound.wonPlayers.isEmpty)
    }

    func testGuaFengXiaYuActivePlayersOnly() throws {
        var game = makeGame(mode: .xuezhan)
        // 玩家 0 先一胡离场
        try game.recordWin(win(0, discarder: 1, fan: 1)) // 1 放铳 2 分 -> [2, -2, 0, 0]

        // 玩家 1 直杠（玩家 2 点杠）：点杠者 2 独付 2 倍底分 = 2 分
        try game.recordKong(KongRecord(player: 1, kind: .zhiGang, discarder: 2))
        XCTAssertEqual(game.records.last?.deltas, [0, 2, -2, 0])

        // 玩家 2 巴杠（弯杠）：在场未胡的 1、3 各付 1 倍底分 = 1 分（已胡的 0 不付）
        try game.recordKong(KongRecord(player: 2, kind: .baGang))
        XCTAssertEqual(game.records.last?.deltas, [0, -1, 2, -1])

        // 玩家 3 下雨（暗杠）：在场未胡的 1、2 各付 2 倍底分 = 2 分（已胡的 0 不付）
        try game.recordKong(KongRecord(player: 3, kind: .anGang))
        XCTAssertEqual(game.records.last?.deltas, [0, -2, -2, 4])
    }

    func testCallTransferOnGangShangPao() throws {
        var game = makeGame(mode: .xuezhan)
        // 玩家 1 暗杠（下雨），向 0、2、3 各收 2 分，共收 6 分
        try game.recordKong(KongRecord(player: 1, kind: .anGang))
        XCTAssertEqual(game.scores, [-2, 6, -2, -2])

        // 紧接着玩家 1 杠后打出一张牌，被玩家 2 胡「杠上炮」（2 番 = 4 分）：
        // 触发呼叫转移！玩家 1 刚才暗杠收到的 6 分原封不动转移给玩家 2，外加点炮牌本身 4 分，合计 1 付 10 分给 2！
        try game.recordWin(win(2, discarder: 1, fan: 2, gangShangPao: true))
        let winRecord = try XCTUnwrap(game.records.last?.outcome.win)
        XCTAssertEqual(winRecord.callTransferAmount, 6, "呼叫转移自动把上一笔杠收到的 6 分转给胡牌者")
        XCTAssertEqual(game.records.last?.deltas, [0, -10, 10, 0])
        XCTAssertEqual(game.scores, [-2, -4, 8, -2])
    }

    func testDrawSettlementTaxRefundHuaZhuAndChaDaJiao() throws {
        var game = makeGame(mode: .xuezhan, fanCap: 4) // 4 番封顶 = 16 倍
        // 0 先胡牌离场（平胡点炮：1 付 1 分给 0）
        try game.recordWin(win(0, discarder: 1, fan: 0))
        XCTAssertEqual(game.scores, [1, -1, 0, 0])

        // 局中杠分：
        // - 玩家 2（稍后未下叫）暗杠收 1、3 各 2 分（共 +4）
        // - 玩家 3（稍后花猪）直杠玩家 1 收 2 分（共 +2）
        // - 玩家 1（稍后下叫 3 番 = 8 倍）巴杠收 2、3 各 1 分（共 +2）
        try game.recordKong(KongRecord(player: 2, kind: .anGang))
        try game.recordKong(KongRecord(player: 3, kind: .zhiGang, discarder: 1))
        try game.recordKong(KongRecord(player: 1, kind: .baGang))
        // 此时分数：0: +1, 1: -1 -2 -2 +2 = -3, 2: +4 -1 = +3, 3: -2 +2 -1 = -1
        XCTAssertEqual(game.scores, [1, -3, 3, -1])

        // 荒庄流局结算：
        // 0: 已胡 (.alreadyWon)
        // 1: 已下叫，大叫 3 番（8 分）(.ting(maxFan: 3))
        // 2: 未下叫 (.notTing) -> 必须退税（暗杠收 1、3 的各 2 分退回），且向已下叫的 1 赔大叫 8 分
        // 3: 花猪 (.huaZhu) -> 必须退税（直杠收 1 的 2 分退回），且向非花猪在场玩家（1、2）各赔封顶 4 番（16 分）！
        // 注意：花猪已经赔了 1 封顶 16 分，不再重复赔 1 的大叫。
        let settlement = try game.recordDrawSettlement(states: [
            .alreadyWon,
            .ting(maxFan: 3),
            .notTing,
            .huaZhu,
        ])
        guard case .drawSettlement(let record) = settlement.outcome else {
            return XCTFail("应为流局查叫记录")
        }
        // 退税校验：
        // 玩家 2 退回给 1(+2)、3(+2)，2 自己 -4
        // 玩家 3 退回给 1(+2)，3 自己 -2
        // 合计退税：0: 0, 1: +4, 2: -4, 3: +2 - 2 = 0
        XCTAssertEqual(record.taxRefundDeltas, [0, 4, -4, 0])

        // 查花猪 + 查大叫赔付校验：
        // - 花猪 3 赔非花猪 1、2 各 16 分 -> [0, +16, +16, -32]
        // - 未下叫 2 赔已下叫 1 大叫 3 番（8 分） -> [0, +8, -8, 0]
        // 合计赔付：[0, +24, +8, -32]
        XCTAssertEqual(record.penaltyDeltas, [0, 24, 8, -32])
        XCTAssertEqual(settlement.deltas, [0, 28, 4, -32])
        XCTAssertEqual(game.currentHandIndex, 1, "荒庄流局结算后推进至下一局")
    }

    func testDianGangHuaAsZimoVsAsDianPaoAndZimoAddFan() throws {
        var game = makeGame(mode: .xuezhan, fanCap: 4, zimo: .addDi)
        // 默认点杠花算自摸（三家付）：0 点杠花 2 番（4 倍 + 加底 1 = 5 分），三家各付 5 分
        try game.recordWin(win(0, discarder: nil, fan: 2, gangShangHua: true, dianGangFrom: 2))
        XCTAssertEqual(game.scores, [15, -5, -5, -5])

        // 切换家规：点杠花算点炮（点杠者 2 包付）+ 自摸加番
        var rules = game.rules
        rules.dianGangHuaRule = .asDianPao
        try game.changeRules(rules)
        // 点杠花算点炮时，不享受自摸加底，2 番 = 4 分由点杠者 2 独付
        XCTAssertEqual(game.scores, [4, 0, -4, 0])

        // 再改回点杠花算自摸，且改为「自摸加番」（2 番 + 1 番 = 3 番 = 8 倍，三家各付 8 分）
        rules.dianGangHuaRule = .asZimo
        rules.zimoRule = .addFan
        try game.changeRules(rules)
        XCTAssertEqual(game.scores, [24, -8, -8, -8])
    }

    func testXueliuAllowsSamePlayerToWinMultipleTimesInOneRound() throws {
        var game = makeGame(mode: .xueliu, fanCap: 4, zimo: .addDi)
        // 血流成河：玩家 0 胡完第一把后仍在场，可以继续胡第二把、第三把
        try game.recordWin(win(0, discarder: 1, fan: 1))
        try game.recordWin(win(0, discarder: nil, fan: 2))
        try game.recordWin(win(2, discarder: 0, fan: 1))
        XCTAssertEqual(game.currentHandIndex, 0, "血流成河胡牌不自动结本局，直到牌摸完结算")
        XCTAssertEqual(game.liveRound.activePlayers, [0, 1, 2, 3])
        XCTAssertEqual(game.liveRound.winCount(of: 0), 2)

        try game.recordDraw()
        XCTAssertEqual(game.currentHandIndex, 1)
    }

    func testPresetsAndArchiveCompatibility() throws {
        var rules = GameRules.standard
        rules.yuanPerPoint = 2
        XCTAssertTrue(rules.scoresLike(.standard), "1分几元不算桌规差异")
        rules.zimoRule = .addFan
        XCTAssertFalse(rules.scoresLike(.standard))

        let json = #"{"games":[{"id":"6E897041-FD3D-4426-B080-2D7BC6E72995","startedAt":"2026-10-26T04:00:00Z","players":[{"id":"6E897041-FD3D-4426-B080-2D7BC6E72991","name":"a"},{"id":"6E897041-FD3D-4426-B080-2D7BC6E72992","name":"b"},{"id":"6E897041-FD3D-4426-B080-2D7BC6E72993","name":"c"},{"id":"6E897041-FD3D-4426-B080-2D7BC6E72994","name":"d"}],"rules":{"yuanPerPoint":2}}]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(GameArchive.self, from: Data(json.utf8))
        XCTAssertEqual(archive.games.first?.rules.yuanPerPoint, 2)
        XCTAssertEqual(archive.games.first?.rules.mode, .xuezhan)
        XCTAssertEqual(archive.games.first?.rules.fanCap, 4)
    }

    func testSpecialWinAvailabilityAndFixSuggestions() {
        let closedHand = Hand(concealed: Tile.parseList("123m 456m 789m 123p 44p"), winningTile: Tile(.dots, 4))
        XCTAssertNil(SpecialWin.kongReplacement.unavailableReason(hand: closedHand, selfDrawn: true))
        XCTAssertNotNil(SpecialWin.kongReplacement.unavailableReason(hand: closedHand, selfDrawn: false))
        XCTAssertNil(SpecialWin.kongPao.unavailableReason(hand: closedHand, selfDrawn: false))
        XCTAssertNotNil(SpecialWin.kongPao.unavailableReason(hand: closedHand, selfDrawn: true))

        let tiles = Tile.parseList("111p 234p 567p 999p 5p 4p") // 4p 应为 5p
        let hand = Hand(concealed: tiles, winningTile: tiles.last)
        let suggestions = WinAssistant.fixSuggestions(for: hand, context: WinContext())
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertEqual(suggestions.first?.from?.suit, .dots)
    }
}

private extension HandOutcome {
    var win: WinRecord? {
        if case .win(let win) = self { return win }
        return nil
    }
}
