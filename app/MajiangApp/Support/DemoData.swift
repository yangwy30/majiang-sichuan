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
    /// 家规：开局页的规则表单、点开一项的选项；牌桌上打到一半改这场的规则（预览底分改成 5）、
    /// 带家规的牌桌、封顶起作用的结果页、带家规的账本图。
    case houseRules = "house-rules", rulePicker = "rule-picker", gameRules = "game-rules"
    case tableHouse = "table-house", resultCapped = "result-capped", shareHouse = "share-house"
    /// 「这一局」：自摸、拍过照的第 1 局；打开那张照片；点炮、有一组碰、没留照片的第 2 局。
    /// 照片默认用演示牌画一张，`-demo-photo <路径>` 可以换成真照片（模拟器能直接读 Mac 上的文件）。
    case handDetail = "hand-detail", handPhoto = "hand-photo", handDiscard = "hand-discard"

    /// 这几页的牌局带家规：封顶 64（结果页用 16，好让示例那手封顶）、1 分 2 元。
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
        win(&older, winner: 2, discarder: 0, hand: "123m 456m 789s 234p 55s")
        win(&older, winner: 0, discarder: nil, hand: "234m 456m 678m 东东东 99m")
        older.end()
        archive.upsert(older)

        var last = Game(players: players, startedAt: Date().addingTimeInterval(-1 * day))
        win(&last, winner: 0, discarder: nil, hand: "1112233445566p 7p")
        win(&last, winner: 3, discarder: 1, hand: "123s 456s 789s 南南南 22m")
        last.end()
        archive.upsert(last)

        var houseRules = GameRules()
        if let screen = DemoScreen.current, screen.usesHouseRules {
            houseRules.kiriageMangan = true
            houseRules.fanCap = screen == .resultCapped ? 5 : 8
            houseRules.yuanPerPoint = 2
        }
        var active = Game(players: players, rules: houseRules)
        win(&active, winner: 0, discarder: nil, hand: "1112233445566p 7p")
        win(&active, winner: 2, discarder: 1, melds: [.pung(Tile(suit: .honors, rank: 6)!)], hand: "234m 345s 45p 88s 6p")
        _ = try? active.recordDraw()
        win(&active, winner: 3, discarder: nil, hand: "234m 456m 678m 东东东 99m")
        archive.upsert(active)

        archive.remember(players + [Player(name: "老王"), Player(name: "小周")])
        return archive
    }

    /// 按真的算番记一手；凑不成或不够番时退回 8 番的无番和，保证有数据。
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
                               fans: [FanEntry(fan: .chickenHand, count: 1)], flowerFan: 0)
        }
        _ = try? game.recordWin(record)
    }

    /// 「这一局」截图用的照片：没打完那场的第 1 局有照片，第 2 局没有。
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
            // 没给真照片：在牌桌颜色的底上摆一排牌
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

    /// 账本图截图用哪场牌局。
    static func shareGame(_ screen: DemoScreen, in archive: GameArchive) -> Game? {
        switch screen {
        case .shareSettle: archive.finishedGames.first
        case .shareLive, .shareHouse: archive.activeGame
        default: nil
        }
    }

    /// 记一局流程里要停的那一步。
    @MainActor
    static func prepare(_ flow: RoundFlow, for screen: DemoScreen) {
        let samples = MockRecognizer.defaultSamples
        // 截图里当作在拍照页已经点了庄家和牌；自摸还是点炮留给核对页选
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
            // Gemini 把一张 5饼 读成 4饼；端侧在中间多读了一张 9条
            var gemini = Recognition(concealed: Tile.parseList("1112233445566p 7p"), source: "Gemini")
            gemini.concealed[9] = RecognizedTile(tile: Tile(suit: .dots, rank: 4)!)
            let onDevice = Recognition(concealed: Tile.parseList("111223p 9s 3445566p 7p"), source: "端侧")
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
