import XCTest
@testable import MajiangKit

final class FanCalculatorTests: XCTestCase {
    func testSichuanFanPointsTable() {
        XCTAssertEqual(Fan.pingHu.points, 0)
        XCTAssertEqual(Fan.duiDuiHu.points, 1)
        XCTAssertEqual(Fan.qingYiSe.points, 2)
        XCTAssertEqual(Fan.qiDui.points, 2)
        XCTAssertEqual(Fan.daiYaoJiu.points, 2)
        XCTAssertEqual(Fan.jinGouDiao.points, 2)
        XCTAssertEqual(Fan.jiangDui.points, 3)
        XCTAssertEqual(Fan.qingDui.points, 3)
        XCTAssertEqual(Fan.longQiDui.points, 3)
        XCTAssertEqual(Fan.qingQiDui.points, 4)
        XCTAssertEqual(Fan.qingDaiYao.points, 4)
        XCTAssertEqual(Fan.qingJinGouDiao.points, 4)
        XCTAssertEqual(Fan.jiangJinGou.points, 4)
        XCTAssertEqual(Fan.qingLongQiDui.points, 5)
        XCTAssertEqual(Fan.tianHu.points, 5)
        XCTAssertEqual(Fan.diHu.points, 5)
        XCTAssertEqual(Fan.shiBaLuoHan.points, 6)
        XCTAssertEqual(Fan.gen.points, 1)
    }

    func testPingHuZeroFanOneMultiplier() throws {
        // 平胡（缺条）：0 番 1 倍
        let hand = Hand(concealed: Tile.parseList("123m 456m 789p 234p 55m"), winningTile: Tile(.characters, 5))
        let result = try FanCalculator.score(hand, context: WinContext()).get()
        XCTAssertTrue(result.contains(.pingHu))
        XCTAssertEqual(result.totalFan, 0)
        XCTAssertEqual(result.baseMultiplier, 1)
    }

    func testHuaZhuThreeSuitsRejected() {
        // 万、筒、条三门俱全（花猪）：不能胡牌
        let hand = Hand(concealed: Tile.parseList("123m 456p 789s 234p 55m"), winningTile: Tile(.characters, 5))
        XCTAssertTrue(hand.isHuaZhu)
        XCTAssertFalse(hand.isMissingOneSuit)
        XCTAssertEqual(FanCalculator.score(hand, context: WinContext()).failure, .missingSuitRequired)
    }

    func testDuiDuiHuQingDuiJiangDuiAndJinGouDiao() throws {
        // 对对胡（1 番 2 倍）
        let duiDui = Hand(melds: [.pung(Tile(.characters, 1))],
                          concealed: Tile.parseList("333m 666p 999p 44m"),
                          winningTile: Tile(.characters, 4))
        let r1 = try FanCalculator.score(duiDui).get()
        XCTAssertTrue(r1.contains(.duiDuiHu))
        XCTAssertEqual(r1.totalFan, 1)

        // 清对（清一色 + 对对胡 = 3 番 8 倍）
        let qingDui = Hand(melds: [.pung(Tile(.dots, 1))],
                           concealed: Tile.parseList("333p 666p 888p 99p"),
                           winningTile: Tile(.dots, 9))
        let r2 = try FanCalculator.score(qingDui).get()
        XCTAssertTrue(r2.contains(.qingDui))
        XCTAssertEqual(r2.totalFan, 3)

        // 将对（全部 2/5/8 组成的对对胡 = 3 番 8 倍）
        let jiangDui = Hand(melds: [.pung(Tile(.characters, 2)), .pung(Tile(.dots, 5))],
                            concealed: Tile.parseList("888m 222p 55m"),
                            winningTile: Tile(.characters, 5))
        let r3 = try FanCalculator.score(jiangDui).get()
        XCTAssertTrue(r3.contains(.jiangDui))
        XCTAssertEqual(r3.totalFan, 3)

        // 金钩钓（4 组碰出，单吊将牌 = 2 番 4 倍）
        let jinGou = Hand(melds: [
            .pung(Tile(.characters, 1)),
            .pung(Tile(.characters, 3)),
            .pung(Tile(.dots, 6)),
            .pung(Tile(.dots, 9)),
        ], concealed: Tile.parseList("44m"), winningTile: Tile(.characters, 4))
        let r4 = try FanCalculator.score(jinGou).get()
        XCTAssertTrue(r4.contains(.jinGouDiao))
        XCTAssertEqual(r4.totalFan, 2)

        // 清金钩钓（4 番 16 倍）
        let qingJinGou = Hand(melds: [
            .pung(Tile(.dots, 1)),
            .pung(Tile(.dots, 3)),
            .pung(Tile(.dots, 6)),
            .pung(Tile(.dots, 8)),
        ], concealed: Tile.parseList("99p"), winningTile: Tile(.dots, 9))
        let r5 = try FanCalculator.score(qingJinGou).get()
        XCTAssertTrue(r5.contains(.qingJinGouDiao))
        XCTAssertEqual(r5.totalFan, 4)

        // 将金钩（4 番 16 倍）+ 1 个杠（1 根 +1 番 = 5 番）
        let jiangJinGou = Hand(melds: [
            .kong(Tile(.characters, 2), concealed: false),
            .pung(Tile(.characters, 5)),
            .pung(Tile(.dots, 2)),
            .pung(Tile(.dots, 8)),
        ], concealed: Tile.parseList("55p"), winningTile: Tile(.dots, 5))
        let r6 = try FanCalculator.score(jiangJinGou).get()
        XCTAssertTrue(r6.contains(.jiangJinGou))
        XCTAssertTrue(r6.contains(.gen))
        XCTAssertEqual(r6.totalFan, 5)
    }

    func testQiDuiLongQiDuiAndGenDeduplication() throws {
        // 暗七对（2 番 4 倍）
        let qiDui = Hand(concealed: Tile.parseList("11m 33m 55m 77m 22p 44p 88p"), winningTile: Tile(.dots, 8))
        let r1 = try FanCalculator.score(qiDui).get()
        XCTAssertTrue(r1.contains(.qiDui))
        XCTAssertFalse(r1.contains(.gen))
        XCTAssertEqual(r1.totalFan, 2)

        // 龙七对（3 番 8 倍）：含 1 组四张相同的牌，该根已计入龙七对，不重复加第 1 根
        let longQiDui = Hand(concealed: Tile.parseList("2222m 44m 66m 33p 55p 99p"), winningTile: Tile(.dots, 9))
        let r2 = try FanCalculator.score(longQiDui).get()
        XCTAssertTrue(r2.contains(.longQiDui))
        XCTAssertFalse(r2.contains(.gen), "龙七对自带的 1 根不重复算")
        XCTAssertEqual(r2.totalFan, 3)

        // 双龙七对（龙七对 3 番 + 额外 1 根 = 4 番 16 倍）
        let shuangLong = Hand(concealed: Tile.parseList("2222m 4444m 66m 33p 99p"), winningTile: Tile(.dots, 9))
        let r3 = try FanCalculator.score(shuangLong).get()
        XCTAssertTrue(r3.contains(.longQiDui))
        XCTAssertEqual(r3.fans.first(where: { $0.fan == .gen })?.count, 1)
        XCTAssertEqual(r3.totalFan, 4)

        // 清龙七对（5 番 32 倍）
        let qingLong = Hand(concealed: Tile.parseList("1111p 22p 44p 66p 77p 99p"), winningTile: Tile(.dots, 9))
        let r4 = try FanCalculator.score(qingLong).get()
        XCTAssertTrue(r4.contains(.qingLongQiDui))
        XCTAssertFalse(r4.contains(.gen))
        XCTAssertEqual(r4.totalFan, 5)
    }

    func testGenCountingInStandardHands() throws {
        // 手牌里有 4 张一样的牌（未开杠：一坎 222m + 顺子 234m）+ 副露碰 5p + 手牌里第 4 张 5p（组成 456p） = 2 根！
        let hand = Hand(melds: [.pung(Tile(.dots, 5))],
                        concealed: Tile.parseList("222m 234m 456p 99m"),
                        winningTile: Tile(.characters, 9))
        XCTAssertEqual(hand.genCount, 2, "手牌与副露合计满 4 张一样的牌均计 1 根")
        let result = try FanCalculator.score(hand).get()
        XCTAssertEqual(result.fans.first(where: { $0.fan == .gen })?.count, 2)
        XCTAssertEqual(result.totalFan, 2)
    }

    func testDaiYaoJiuAndMenQingZhongZhang() throws {
        // 带幺九（全带幺，2 番）
        let daiYao = Hand(concealed: Tile.parseList("123m 789m 123p 999p 11m"), winningTile: Tile(.characters, 1))
        let r1 = try FanCalculator.score(daiYao).get()
        XCTAssertTrue(r1.contains(.daiYaoJiu))
        XCTAssertEqual(r1.totalFan, 2)

        // 门清 + 中张（开启可选开关时各 +1 番）
        let menQingZhongZhang = Hand(concealed: Tile.parseList("234m 456m 345p 678p 55m"), winningTile: Tile(.characters, 5))
        let ctx = WinContext(allowMenQing: true, allowZhongZhang: true)
        let r2 = try FanCalculator.score(menQingZhongZhang, context: ctx).get()
        XCTAssertTrue(r2.contains(.menQing))
        XCTAssertTrue(r2.contains(.zhongZhang))
        XCTAssertEqual(r2.totalFan, 2)
    }

    func testCheckTingHuaZhuNotTingAndDaJiao() {
        // 1. 13 张三门俱全 -> 花猪
        let huaZhu13 = Hand(concealed: Tile.parseList("123m 456p 789s 234p 5m"))
        let c1 = WinAssistant.checkTing(huaZhu13)
        XCTAssertEqual(c1.status, .huaZhu)

        // 2. 13 张缺一门但未下叫
        let notTing13 = Hand(concealed: Tile.parseList("147m 258m 147p 258p 9p"))
        let c2 = WinAssistant.checkTing(notTing13)
        XCTAssertEqual(c2.status, .notTing)

        // 3. 13 张查大叫：九莲宝灯清一色听 1~9筒，其中胡 1筒 或 9筒 时凑满 4 张生根（清一色 2 番 + 1 根 = 大叫 3 番）
        let ting13 = Hand(concealed: Tile.parseList("1112345678999p"))
        let c3 = WinAssistant.checkTing(ting13)
        XCTAssertEqual(c3.status, .ting)
        XCTAssertEqual(c3.waits.count, 9)
        XCTAssertEqual(c3.maxFan, 3)
        XCTAssertEqual(c3.bestWait?.tile, Tile(.dots, 1))
    }

    func testErrors() {
        let short = Hand(concealed: Tile.parseList("123m456m789m11p"))
        XCTAssertEqual(FanCalculator.score(short, context: WinContext()).failure, .wrongTileCount)

        let five = Hand(concealed: Tile.parseList("11111m456m789m123p"))
        XCTAssertEqual(FanCalculator.score(five, context: WinContext()).failure, .tileMoreThanFour)

        let noWin = Hand(concealed: Tile.parseList("13579m2468p13579p"))
        XCTAssertEqual(FanCalculator.score(noWin, context: WinContext()).failure, .notAWin)
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
