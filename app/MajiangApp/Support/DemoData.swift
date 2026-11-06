import SwiftUI
import MajiangKit

/// 截图用：启动参数 `-demo-screen <页面>` 打开一份假数据，直接停在某个页面。
/// 数据存在临时目录，不会碰真的牌局记录。只在开发版里有。
enum DemoScreen: String {
    case emptyHome = "empty-home"
    case home, newGame = "new-game", table, editHand = "edit-hand", capture, check, notWin = "not-win", result, settle
    /// 双读：端侧结果已显示、Gemini 还在复核；复核完、有一张两边读得不一样和一张只有一边读到。
    case reviewing = "check-reviewing", dualRead = "check-dual"
    /// 发到群里的账本图：打完的结算 / 没打完的牌局；备份与换手机页。
    case shareSettle = "share-settle", shareLive = "share-live", backup
    /// 首页上打开填邀请码的页；首页右上「更多」升起的那一页。
    case invite, more
    /// 家规：开局页的规则表单、点开一项的选项；牌桌上打到一半改这场的规则、
    /// 带家规的牌桌、封顶起作用的结果页、带家规的账本图。
    case houseRules = "house-rules", rulePicker = "rule-picker", gameRules = "game-rules"
    case tableHouse = "table-house", resultCapped = "result-capped", shareHouse = "share-house"
    /// 「这一局」：自摸、拍过照的第 1 局；打开那张照片；点炮、有一组碰、没留照片的第 2 局。
    case handDetail = "hand-detail", handPhoto = "hand-photo", handDiscard = "hand-discard"

    var usesHouseRules: Bool { [.gameRules, .tableHouse, .resultCapped, .shareHouse].contains(self) }

    static var current: DemoScreen? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demo-screen"), i + 1 < args.count else { return nil }
        return DemoScreen(rawValue: args[i + 1])
        #else
        return nil
        #endif
    }

    /// 在牌桌上自动打开记一局。
    var opensRound: Bool { [.capture, .check, .notWin, .result, .resultCapped, .reviewing, .dualRead].contains(self) }
}

#if DEBUG
enum DemoData {
    static let names = ["杨", "阿强", "莉莉", "小张"]

    static func archive() -> GameArchive {
        var archive = GameArchive()
        let players = names.map { Player(name: $0) }
        let day: TimeInterval = 86_400

        var older = Game(players: [players[0], players[1], Player(name: "老王"), players[3]], startedAt: Date().addingTimeInterval(-8 * day))
        win(&older, winner: 2, discarder: 0, hand: "123m 456m 789p 234p 55m")
        win(&older, winner: 0, discarder: nil, hand: "234m 456m 678m 888p 99m")
        older.end()
        archive.upsert(older)

        var last = Game(players: players, startedAt: Date().addingTimeInterval(-1 * day))
        win(&last, winner: 0, discarder: nil, hand: "1112233445566p 7p")
        win(&last, winner: 3, discarder: 1, hand: "123s 456s 789s 888m 22m")
        last.end()
        archive.upsert(last)

        var houseRules = GameRules()
        if let screen = DemoScreen.current, screen.usesHouseRules {
            houseRules.zimoRule = .addFan
            houseRules.fanCap = screen == .resultCapped ? 3 : 5
            houseRules.yuanPerPoint = 2
        }
        var active = Game(players: players, rules: houseRules)
        win(&active, winner: 0, discarder: nil, hand: "1112233445566p 7p")
        _ = try? active.recordKong(KongRecord(player: 2, kind: .anGang, tile: Tile(suit: .characters, rank: 8)!))
        win(&active, winner: 2, discarder: 1, melds: [.pung(Tile(suit: .dots, rank: 6)!)], hand: "234m 345m 45p 88m 6p")
        _ = try? active.recordDrawSettlement(states: [.alreadyWon, .notTing, .alreadyWon, .ting(maxFan: 2)])
        win(&active, winner: 3, discarder: nil, hand: "234m 456m 678m 888p 99m")
        archive.upsert(active)

        archive.remember(players + [Player(name: "老王"), Player(name: "小周")])
        return archive
    }

    private static func win(_ game: inout Game, winner: Int, discarder: Int?, melds: [Meld] = [], hand text: String) {
        let tiles = Tile.parseList(text)
        let hand = Hand(melds: melds, concealed: tiles, winningTile: tiles.last)
        var context = game.winContext(for: winner)
        context.selfDrawn = discarder == nil
        let record: WinRecord
        if case .success(let result) = FanCalculator.score(hand, context: context), result.meetsMinimum(game.rules.minimumFan) {
            record = WinRecord(winner: winner, discarder: discarder, hand: hand, context: context, result: result)
        } else {
            record = WinRecord(winner: winner, discarder: discarder, hand: nil, context: context,
                               fans: [FanEntry(fan: .pingHu, count: 1, han: 0)])
        }
        _ = try? game.recordWin(record)
    }

    @MainActor
    static func preparePhotos(_ archive: GameArchive) {
        let directory = HandPhotos.directory
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
        guard let record = archive.activeGame?.records.first, let hand = record.win?.hand else { return }
        let args = ProcessInfo.processInfo.arguments
        var image: UIImage?
        if let i = args.firstIndex(of: "-demo-photo"), i + 1 < args.count { image = UIImage(contentsOfFile: args[i + 1]) }
        if image == nil {
            let renderer = ImageRenderer(content:
                TileRow(tiles: hand.allTiles, width: 60)
                    .padding(.horizontal, 60)
                    .frame(width: 1200, height: 900)
                    .background(Color(hex: 0xC9796B)))
            renderer.scale = 1
            image = renderer.uiImage
        }
        if let image, let data = HandPhotos.compressed(image) {
            try? data.write(to: HandPhotos.url(for: record.id), options: .atomic)
        }
    }

    static func shareGame(_ screen: DemoScreen, in archive: GameArchive) -> Game? {
        switch screen {
        case .shareSettle: archive.finishedGames.first
        case .shareLive, .shareHouse: archive.activeGame
        default: nil
        }
    }

    @MainActor
    static func prepare(_ flow: RoundFlow, for screen: DemoScreen) {
        let samples = MockRecognizer.defaultSamples
        if screen != .capture { flow.pickWinner(flow.game.dealer) }
        switch screen {
        case .check:
            flow.load(samples[0])
            flow.steps = [.check]
        case .notWin:
            flow.load(samples[2])
            flow.steps = [.check]
        case .reviewing:
            flow.load(Recognition(concealed: Tile.parseList("1112233445566p 7p"), source: "端侧"))
            flow.isReviewing = true
            flow.steps = [.check]
        case .dualRead:
            var gemini = Recognition(concealed: Tile.parseList("1112233445566p 7p"), source: "Gemini")
            gemini.concealed[9] = RecognizedTile(tile: Tile(suit: .dots, rank: 4)!)
            let onDevice = Recognition(concealed: Tile.parseList("111223p 9m 3445566p 7p"), source: "端侧")
            flow.load(DualReadRecognizer.merge(gemini, with: onDevice))
            flow.steps = [.check]
        case .result, .resultCapped:
            flow.load(samples[0])
            flow.choose(Tile(suit: .dots, rank: 5)!, at: 9)
            flow.pickSelfDrawn()
            flow.steps = [.check]
            flow.showResult = true
        default:
            break
        }
    }
}
#endif
