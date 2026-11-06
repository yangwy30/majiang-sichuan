import XCTest
@testable import MajiangKit

final class GameTests: XCTestCase {
    private func makeGame(swap: Bool = false) -> Game {
        var rules = GameRules()
        rules.swapSeatsEachRound = swap
        rules.yuanPerPoint = 1
        return Game(players: ["杨", "小周", "阿乐", "老王"].map { Player(name: $0) }, rules: rules)
    }

    private func win(_ winner: Int, discarder: Int?, fan: Int, dora: Int = 0, fu: Int = 30) -> WinRecord {
        WinRecord(
            winner: winner,
            discarder: discarder,
            hand: nil,
            context: WinContext(flowerCount: dora),
            fans: [FanEntry(fan: .riichi, count: 1, han: fan - dora)],
            flowerFan: dora,
            fu: fu
        )
    }

    func testRiichiPayments() {
        // 庄家（0）自摸满贯（5 翻）：三家各付 4000，庄家 +12000
        XCTAssertEqual(
            Payment.winDeltas(winner: 0, discarder: nil, dealer: 0, totalFan: 5, fu: 30),
            [12000, -4000, -4000, -4000]
        )
        // 闲家（2）荣和（1 放铳）30 符 3 翻：基本点 960，闲家荣和 3840 -> 3900
        XCTAssertEqual(
            Payment.winDeltas(winner: 2, discarder: 1, dealer: 0, totalFan: 3, fu: 30),
            [0, -3900, 3900, 0]
        )
        // 闲家（2）自摸 30 符 3 翻：基本点 960，庄家付 2000，另外两闲家各付 1000
        XCTAssertEqual(
            Payment.winDeltas(winner: 2, discarder: nil, dealer: 0, totalFan: 3, fu: 30),
            [-2000, -1000, 4000, -1000]
        )
        // 错和罚符：赔三家各 3000 点
        XCTAssertEqual(Payment.falseWinDeltas(offender: 3, penalty: 3000), [3000, 3000, 3000, -9000])
    }

    func testKiriageManganAndFanCap() {
        // 30 符 4 翻：默认 7700（闲家荣和），开启切上满贯为 8000
        var standard = GameRules.standard
        XCTAssertEqual(
            Payment.winDeltas(winner: 2, discarder: 1, dealer: 0, totalFan: 4, fu: 30, rules: standard),
            [0, -7700, 7700, 0]
        )
        standard.kiriageMangan = true
        XCTAssertEqual(
            Payment.winDeltas(winner: 2, discarder: 1, dealer: 0, totalFan: 4, fu: 30, rules: standard),
            [0, -8000, 8000, 0]
        )

        // 封顶 8 翻（倍满 16000）：13 翻按 8 翻算
        var capped = GameRules.standard
        capped.fanCap = 8
        XCTAssertEqual(
            Payment.winDeltas(winner: 3, discarder: 2, dealer: 0, totalFan: 13, fu: 30, rules: capped),
            [0, 0, -16000, 16000]
        )
    }

    func testPresets() {
        var rules = GameRules.standard
        rules.yuanPerPoint = 2
        XCTAssertTrue(rules.scoresLike(.standard), "1000 点几元不算桌规差异")
        rules.kiriageMangan = true
        XCTAssertFalse(rules.scoresLike(.standard))
        XCTAssertEqual(GameRules.standard.totalHands, 8)
        XCTAssertEqual(GameRules.beginner.totalHands, 4)
        XCTAssertEqual(GameRules.standard.minimumFan, 1)
    }

    func testChangingRulesRecomputesEveryHand() throws {
        var game = makeGame()
        // 第 1 局（东 1，庄 0）：闲家 2 荣和 1，30 符 4 翻（默认 7700，切上满贯 8000）
        try game.recordWin(win(2, discarder: 1, fan: 4, fu: 30))
        XCTAssertEqual(game.scores, [0, -7700, 7700, 0])

        var rules = game.rules
        rules.kiriageMangan = true
        let preview = try game.changingRules(rules)
        XCTAssertEqual(preview.scores, [0, -8000, 8000, 0])
        XCTAssertEqual(game.scores, [0, -7700, 7700, 0], "预览不改原来的牌局")

        try game.changeRules(rules)
        XCTAssertEqual(game.scores, [0, -8000, 8000, 0])
        XCTAssertEqual(game.scores.reduce(0, +), 0)

        // 起和调高到 2 翻：前面只有 1 翻役的和牌留着，标出来
        var twoHan = makeGame()
        try twoHan.recordWin(win(2, discarder: 1, fan: 1, fu: 30))
        var strictRules = twoHan.rules
        strictRules.minimumFan = 2
        try twoHan.changeRules(strictRules)
        XCTAssertEqual(twoHan.winsBelowMinimum.map(\.handIndex), [0])

        // 中途改成不计宝牌：去掉宝牌翻数再算
        var doraGame = makeGame()
        try doraGame.recordWin(win(2, discarder: 1, fan: 5, dora: 2, fu: 30)) // 含宝牌 5 翻满贯 8000
        XCTAssertEqual(doraGame.scores[2], 8000)
        var noDora = doraGame.rules
        noDora.includeFlowers = false
        try doraGame.changeRules(noDora)
        XCTAssertEqual(doraGame.scores[2], 3900) // 去掉 2 张宝牌变 30 符 3 翻 = 3900
    }

    func testRulesRememberedPerGroupOfPlayers() {
        var archive = GameArchive()
        var house = GameRules()
        house.kiriageMangan = true
        archive.start(Game(players: ["杨", "阿强", "莉莉", "小张"].map { Player(name: $0) }, rules: house,
                           startedAt: Date(timeIntervalSince1970: 100)))
        archive.start(Game(players: ["杨", "小周", "阿乐", "老王"].map { Player(name: $0) },
                           startedAt: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(archive.lastRules(forPlayers: ["小张", "杨", "莉莉", "阿强"])?.kiriageMangan, true, "座位换了也认得")
        XCTAssertNil(archive.lastRules(forPlayers: ["杨", "阿强", "莉莉", "老王"]))
    }

    func testOldRulesWithoutHouseRuleFieldsStillLoad() throws {
        let json = #"{"yuanPerPoint":1,"minimumFan":1,"includeFlowers":true}"#
        let rules = try JSONDecoder().decode(GameRules.self, from: Data(json.utf8))
        XCTAssertEqual(rules.fanCap, 0)
        XCTAssertFalse(rules.kiriageMangan)
    }

    func testDealerAndWindsRotateWithoutSwap() {
        var game = makeGame()
        XCTAssertEqual(game.dealer, 0)
        XCTAssertEqual(game.prevalentWind, .east)
        XCTAssertEqual((0..<4).map { game.seatWind(of: $0) }, [.east, .south, .west, .north])

        try! game.recordDraw()
        XCTAssertEqual(game.dealer, 1)
        XCTAssertEqual((0..<4).map { game.seatWind(of: $0) }, [.north, .east, .south, .west])

        for _ in 0..<3 { try! game.recordDraw() }
        XCTAssertEqual(game.currentHandIndex, 4)
        XCTAssertEqual(game.prevalentWind, .south)
        XCTAssertEqual(game.dealer, 0)
    }

    func testRecordingAndLedger() throws {
        var game = makeGame()
        // 第 1 局（东 1，庄 0）：庄家自摸满贯（5 翻） -> 三家各 -4000，庄 +12000
        try game.recordWin(win(0, discarder: nil, fan: 5))
        // 第 2 局（东 2，庄 1）：闲家 2 荣和 1 满贯（3 翻役 + 2 宝牌） -> 1 付 8000
        try game.recordWin(win(2, discarder: 1, fan: 5, dora: 2))
        // 错和（3 赔三家各 3000）
        try game.recordFalseWin(offender: 3)
        XCTAssertEqual(game.currentHandIndex, 2, "错和不推进局数")
        XCTAssertEqual(game.scores, [12000 + 3000, -4000 - 8000 + 3000, -4000 + 8000 + 3000, -4000 - 9000])
        XCTAssertEqual(game.scores.reduce(0, +), 0)
        XCTAssertEqual(game.money(forPoints: game.scores[0]), 15)
        XCTAssertEqual(game.biggestWin?.win.winner, 0)

        game.undoLast()
        XCTAssertEqual(game.records.count, 2)
    }

    func testRejectsInvalidWins() {
        var game = makeGame()
        XCTAssertThrowsError(try game.recordWin(win(0, discarder: 0, fan: 1)))
        // 只有宝牌、没有役（0 翻役 + 3 张宝牌）：无役不能和
        let noYaku = WinRecord(winner: 0, discarder: 1, hand: nil, context: WinContext(flowerCount: 3),
                               fans: [], flowerFan: 3)
        XCTAssertThrowsError(try game.recordWin(noYaku)) { error in
            XCTAssertEqual(error as? GameError, .belowMinimumFan(0))
        }
        XCTAssertThrowsError(try game.recordManual(deltas: [1000, 2000, 3000, 4000]))
    }

    func testGameFinishesAfterEightHands() throws {
        var game = makeGame()
        for _ in 0..<8 { try game.recordDraw() }
        XCTAssertTrue(game.isFinished)
        XCTAssertThrowsError(try game.recordDraw())
    }

    func testEditingAnEarlierWinRecomputesTheLedger() throws {
        var game = makeGame()
        let first = try game.recordWin(win(0, discarder: 1, fan: 5)) // 庄荣和满贯 12000
        try game.recordWin(win(2, discarder: nil, fan: 5)) // 第 2 局（庄 1）：闲 2 自摸满贯（庄 1 付 4000，0/3 各付 2000）
        // 第一局改成闲家 2 荣和 3 满贯（8000）
        var fixed = win(2, discarder: 3, fan: 5)
        fixed.context = game.records[0].outcome.win!.context
        try game.replace(first.id, with: .win(fixed))
        XCTAssertEqual(game.records[0].id, first.id)
        XCTAssertEqual(game.records[0].deltas, [0, 0, 8000, -8000])
        XCTAssertEqual(game.records[1].deltas, [-2000, -4000, 8000, -2000])
        XCTAssertEqual(game.records[0].outcome.win?.context.seatWind, .west, "自风跟着和牌的人换")
    }

    func testRemovingAHandMovesLaterWinsAndRescoresWinds() throws {
        var game = makeGame()
        let draw = try game.recordDraw()
        // 第二局（东 2，庄 1）老王（下标 3，此时自风为西）和：西风刻 + 断幺不可共立，这里加白板刻保底 1 翻
        let tiles = Hand(concealed: Tile.parseList("西西西 白白白 123m 456m 9m9m"), winningTile: Tile(.characters, 9))
        let context = game.winContext(for: 3)
        let result = try FanCalculator.score(tiles, context: context).get()
        XCTAssertTrue(result.contains(.seatWind))
        try game.recordWin(WinRecord(winner: 3, discarder: 0, hand: tiles, context: context, result: result))

        game.remove(draw.id)
        XCTAssertEqual(game.records.count, 1)
        XCTAssertEqual(game.records[0].handIndex, 0)
        let moved = try XCTUnwrap(game.records[0].outcome.win)
        XCTAssertEqual(moved.context.seatWind, .north, "挪到第一局，老王是北家")
        XCTAssertFalse(moved.fans.contains { $0.fan == .seatWind })
    }

    func testSwitchingSelfDrawnRescoresTheHand() throws {
        var game = makeGame()
        let tiles = Hand(concealed: Tile.parseList("1p 1p 1p 2p 2p 3p 3p 4p 4p 5p 5p 6p 6p 7p"))
        var context = game.winContext(for: 0)
        context.selfDrawn = true
        context.lastTileOfWall = true
        let result = try FanCalculator.score(tiles, context: context).get()
        let record = try game.recordWin(WinRecord(winner: 0, discarder: nil, hand: tiles, context: context, result: result))

        var edited = try XCTUnwrap(record.outcome.win)
        edited.discarder = 2
        try game.replace(record.id, with: .win(edited))
        let rescored = try XCTUnwrap(game.records[0].outcome.win)
        XCTAssertFalse(rescored.context.selfDrawn)
        XCTAssertFalse(rescored.context.lastTileOfWall, "海底摸月换成点炮就不成立了")
        XCTAssertFalse(rescored.fans.contains { $0.fan == .menzenTsumo })
    }

    func testSpecialWinAvailability() {
        let closedHand = Hand(concealed: Tile.parseList("123m 456m 789m 123p 44p"), winningTile: Tile(.dots, 4))
        XCTAssertNil(SpecialWin.riichi.unavailableReason(hand: closedHand, selfDrawn: false))
        XCTAssertNotNil(SpecialWin.kongReplacement.unavailableReason(hand: closedHand, selfDrawn: true))
        XCTAssertNil(SpecialWin.lastTileDraw.unavailableReason(hand: closedHand, selfDrawn: true))
        XCTAssertNotNil(SpecialWin.lastTileClaim.unavailableReason(hand: closedHand, selfDrawn: true))

        let openHand = Hand(melds: [.chow(Tile(.characters, 1))!],
                            concealed: Tile.parseList("456m 789m 123p 44p"), winningTile: Tile(.dots, 4))
        XCTAssertNotNil(SpecialWin.riichi.unavailableReason(hand: openHand, selfDrawn: true))
    }

    func testFixSuggestionsFindMisreadPip() {
        let tiles = Tile.parseList("111p 234p 567p 999p 5p 4p") // 4p 应为 5p
        let hand = Hand(concealed: tiles, winningTile: tiles.last)
        let suggestions = WinAssistant.fixSuggestions(for: hand, context: WinContext())
        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertEqual(suggestions.first?.from?.suit, .dots)
        XCTAssertEqual(suggestions.first.map { abs($0.from!.rank - $0.to.rank) }, 1)

        // 少读一张：补一张就能和
        let short = Hand(concealed: Array(Tile.parseList("111p 234p 567p 999p 5p")), winningTile: Tile(.dots, 5))
        let add = WinAssistant.fixSuggestions(for: short, context: WinContext())
        XCTAssertTrue(add.contains { $0.to == Tile(.dots, 5) })
        XCTAssertTrue(add.allSatisfy { $0.index == nil })
    }
}

final class ArchiveAndParsingTests: XCTestCase {
    func testOldArchiveWithMissingFieldsStillLoads() throws {
        let json = #"{"games":[{"id":"6E897041-FD3D-4426-B080-2D7BC6E72995","startedAt":"2026-10-26T04:00:00Z","players":[{"id":"6E897041-FD3D-4426-B080-2D7BC6E72991","name":"a"},{"id":"6E897041-FD3D-4426-B080-2D7BC6E72992","name":"b"},{"id":"6E897041-FD3D-4426-B080-2D7BC6E72993","name":"c"},{"id":"6E897041-FD3D-4426-B080-2D7BC6E72994","name":"d"}],"rules":{"yuanPerPoint":2}}]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(GameArchive.self, from: Data(json.utf8))
        XCTAssertEqual(archive.games.first?.rules.yuanPerPoint, 2)
        XCTAssertEqual(archive.games.first?.rules.totalHands, 8)
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.games.first?.me, 0)
    }

    func testNoFixSuggestionsForNoYakuWinningShape() {
        // 牌型成立但无役：不要建议把牌改成别的牌
        let hand = Hand(melds: [.chow(Tile(.characters, 1))!],
                        concealed: Tile.parseList("345p 678s 234s 99m"), winningTile: Tile(.characters, 9))
        XCTAssertTrue(WinAssistant.fixSuggestions(for: hand, context: WinContext()).isEmpty)
    }

    func testSpecialWinConflicts() {
        XCTAssertTrue(SpecialWin.riichi.conflicts.contains(.doubleRiichi))
        XCTAssertTrue(SpecialWin.kongReplacement.conflicts.contains(.lastTileDraw))
        XCTAssertTrue(SpecialWin.lastTileClaim.conflicts.contains(.robbingTheKong))
    }
}

private extension HandOutcome {
    var win: WinRecord? {
        if case .win(let win) = self { return win }
        return nil
    }
}
