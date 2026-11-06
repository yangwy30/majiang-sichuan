import XCTest
@testable import MajiangKit

final class FanCalculatorTests: XCTestCase {
    func testYakuTableBasics() {
        XCTAssertEqual(Fan.riichi.points, 1)
        XCTAssertEqual(Fan.tanyao.points, 1)
        XCTAssertEqual(Fan.pinfu.points, 1)
        XCTAssertEqual(Fan.chiitoitsu.points, 2)
        XCTAssertEqual(Fan.toitoi.points, 2)
        XCTAssertEqual(Fan.honitsu.points, 3)
        XCTAssertEqual(Fan.honitsu.openPoints, 2)
        XCTAssertEqual(Fan.chinitsu.points, 6)
        XCTAssertEqual(Fan.chinitsu.openPoints, 5)
        XCTAssertEqual(Fan.kokushi.points, 13)
        XCTAssertTrue(Fan.kokushi.isYakuman)
    }

    func testMenzenPinfuTsumo20Fu() throws {
        // 门前清 · 平和 · 自摸 · 一杯口：20 符 3 翻
        let hand = Hand(concealed: Tile.parseList("223344m 456p 678s 99p"), winningTile: Tile(.characters, 4))
        let result = try FanCalculator.score(hand, context: WinContext(selfDrawn: true)).get()
        XCTAssertTrue(result.contains(.pinfu))
        XCTAssertTrue(result.contains(.iipeiko))
        XCTAssertTrue(result.contains(.menzenTsumo))
        XCTAssertEqual(result.fu, 20)
        XCTAssertEqual(result.totalFan, 3)
        XCTAssertTrue(result.meetsMinimum())
    }

    func testMenzenPinfuRon30Fu() throws {
        // 门前清 · 平和 · 断幺九 · 荣和：30 符 2 翻
        let hand = Hand(concealed: Tile.parseList("234m 456p 678s 345p 66s"), winningTile: Tile(.characters, 2))
        let result = try FanCalculator.score(hand, context: WinContext(selfDrawn: false)).get()
        XCTAssertTrue(result.contains(.pinfu))
        XCTAssertTrue(result.contains(.tanyao))
        XCTAssertEqual(result.fu, 30)
        XCTAssertEqual(result.totalFan, 2)
    }

    func testChiitoitsuFixed25Fu() throws {
        // 七对子 + 断幺九：固定 25 符 3 翻
        let hand = Hand(concealed: Tile.parseList("22m 44m 66p 88p 33s 55s 77s"), winningTile: Tile(.bamboo, 7))
        let result = try FanCalculator.score(hand, context: WinContext(selfDrawn: false)).get()
        XCTAssertTrue(result.contains(.chiitoitsu))
        XCTAssertTrue(result.contains(.tanyao))
        XCTAssertEqual(result.fu, 25)
        XCTAssertEqual(result.totalFan, 3)
    }

    func testFourIdenticalTilesDoNotCountAsChiitoitsu() {
        // 日麻规定 4 张相同的牌不能算作七对子里的两对
        let hand = Hand(concealed: Tile.parseList("2222m 44p 66p 88p 33s 55s"), winningTile: Tile(.bamboo, 5))
        XCTAssertEqual(FanCalculator.score(hand, context: WinContext()).failure, .notAWin)
    }

    func testRyanpeikoBeatsChiitoitsu() throws {
        // 二杯口（3 翻）同时满足 7 个对子，高点法应取二杯口 + 平和（4 翻）而非七对子（2 翻）
        let hand = Hand(concealed: Tile.parseList("223344m 556677p 88s"), winningTile: Tile(.characters, 4))
        let result = try FanCalculator.score(hand, context: WinContext(selfDrawn: false)).get()
        XCTAssertTrue(result.contains(.ryanpeiko))
        XCTAssertFalse(result.contains(.chiitoitsu))
        XCTAssertTrue(result.contains(.pinfu))
        XCTAssertTrue(result.contains(.tanyao))
        XCTAssertEqual(result.totalFan, 5)
    }

    func testKuisagariOpenHandDecreasesHan() throws {
        // 清一色：门前 6 翻，副露 5 翻
        let closed = Hand(concealed: Tile.parseList("1112233445566p 7p"))
        let closedRes = try FanCalculator.score(closed, context: WinContext(selfDrawn: true)).get()
        XCTAssertTrue(closedRes.contains(.chinitsu))
        XCTAssertEqual(closedRes.fans.first(where: { $0.fan == .chinitsu })?.points, 6)

        let open = Hand(melds: [.chow(Tile(.dots, 1))!],
                        concealed: Tile.parseList("234p 456p 678p 99p"),
                        winningTile: Tile(.dots, 8))
        let openRes = try FanCalculator.score(open, context: WinContext(selfDrawn: false)).get()
        XCTAssertTrue(openRes.contains(.chinitsu))
        XCTAssertEqual(openRes.fans.first(where: { $0.fan == .chinitsu })?.points, 5)
    }

    func testDoraDoesNotCountTowardMinimumYaku() throws {
        // 副露后无役（只有顺子，非断幺、非役牌），即便有 5 张宝牌也不能和（无役）
        let hand = Hand(melds: [.chow(Tile(.characters, 1))!],
                        concealed: Tile.parseList("345p 678s 234s 99m"),
                        winningTile: Tile(.characters, 9))
        let result = try FanCalculator.score(hand, context: WinContext(flowerCount: 5)).get()
        XCTAssertEqual(result.fanWithoutFlowers, 0)
        XCTAssertEqual(result.flowerFan, 5)
        XCTAssertFalse(result.meetsMinimum(1))
    }

    func testRiichiAndIppatsuAndDora() throws {
        // 立直 + 一发 + 宝牌 2：本来无役的门前荣和牌，立直后可和
        let hand = Hand(concealed: Tile.parseList("123m 345p 678s 234s 99m"), winningTile: Tile(.characters, 9))
        let context = WinContext(selfDrawn: false, riichi: true, ippatsu: true, flowerCount: 2)
        let result = try FanCalculator.score(hand, context: context).get()
        XCTAssertTrue(result.contains(.riichi))
        XCTAssertTrue(result.contains(.ippatsu))
        XCTAssertEqual(result.fanWithoutFlowers, 2)
        XCTAssertEqual(result.totalFan, 4)
        XCTAssertEqual(result.fu, 40) // 20 副底 + 10 门前荣和 + 2 单骑 = 32 -> 40 符
        XCTAssertTrue(result.meetsMinimum())
    }

    func testSuuankouTankiVsShanponRon() throws {
        // 双碰听牌：荣和 7m 时完成的刻子算明刻，只能算对对和 + 三暗刻（4 翻），自摸才是四暗刻（役满）
        let shanpon = Hand(concealed: Tile.parseList("111m 333p 555s 777m 99p"), winningTile: Tile(.characters, 7))
        let ronResult = try FanCalculator.score(shanpon, context: WinContext(selfDrawn: false)).get()
        XCTAssertFalse(ronResult.contains(.suuankou))
        XCTAssertTrue(ronResult.contains(.toitoi))
        XCTAssertTrue(ronResult.contains(.sanankou))

        let tsumoResult = try FanCalculator.score(shanpon, context: WinContext(selfDrawn: true)).get()
        XCTAssertTrue(tsumoResult.contains(.suuankou))
        XCTAssertTrue(tsumoResult.isYakuman)

        // 单骑听雀头：荣和也是四暗刻单骑（役满）
        let tanki = Hand(concealed: Tile.parseList("111m 333p 555s 777m 99p"), winningTile: Tile(.dots, 9))
        let tankiRon = try FanCalculator.score(tanki, context: WinContext(selfDrawn: false)).get()
        XCTAssertTrue(tankiRon.contains(.suuankou))
    }

    func testKokushiMusouYakuman() throws {
        let hand = Hand(concealed: Tile.parseList("19m 19p 19s 东南西北中发白 1m"), winningTile: Tile(.characters, 1))
        let result = try FanCalculator.score(hand, context: WinContext(flowerCount: 3)).get()
        XCTAssertTrue(result.contains(.kokushi))
        XCTAssertTrue(result.isYakuman)
        XCTAssertEqual(result.flowerFan, 0, "役满不额外加计宝牌")
        XCTAssertEqual(result.totalFan, 13)
    }

    func testErrors() {
        let short = Hand(concealed: Tile.parseList("123m456m789m11p"))
        XCTAssertEqual(FanCalculator.score(short, context: WinContext()).failure, .wrongTileCount)

        let five = Hand(concealed: Tile.parseList("11111m456m789m123p"))
        XCTAssertEqual(FanCalculator.score(five, context: WinContext()).failure, .tileMoreThanFour)

        let noWin = Hand(concealed: Tile.parseList("13579m2468p135s东南"))
        XCTAssertEqual(FanCalculator.score(noWin, context: WinContext()).failure, .notAWin)
    }

    func testWindPungsAndDoubleEast() throws {
        let hand = Hand(concealed: Tile.parseList("南南南 西西西 123m 7m8m9m 1p1p"), winningTile: Tile(.dots, 1))
        let context = WinContext(prevalentWind: .south, seatWind: .west)
        let result = try FanCalculator.score(hand, context: context).get()
        XCTAssertTrue(result.contains(.prevalentWind))
        XCTAssertTrue(result.contains(.seatWind))

        // 连风牌（东场东家摸东刻）：同时计场风东 + 自风东 = 2 翻
        let doubleEast = Hand(concealed: Tile.parseList("东东东 234m 456p 678s 1p1p"), winningTile: Tile(.dots, 1))
        let eastResult = try FanCalculator.score(doubleEast, context: WinContext(prevalentWind: .east, seatWind: .east)).get()
        XCTAssertTrue(eastResult.contains(.prevalentWind))
        XCTAssertTrue(eastResult.contains(.seatWind))
        XCTAssertEqual(eastResult.fanWithoutFlowers, 2)
    }

    func testWaitingTiles() {
        // 九莲宝灯听九面
        let waits = FanCalculator.waitingTiles(melds: [], standing: Tile.parseList("1112345678999m"))
        XCTAssertEqual(waits, (1...9).map { Tile(.characters, $0) })
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
