import XCTest
@testable import MajiangKit

final class ArchiveMergeTests: XCTestCase {
    private let names = ["杨", "小周", "阿乐", "老王"]

    private func makeGame(startedAt: Date) -> Game {
        Game(players: names.map { Player(name: $0) }, startedAt: startedAt)
    }

    func testMergeAddsNewGamesAndKeepsLocalOnes() throws {
        var mine = GameArchive()
        var old = makeGame(startedAt: Date(timeIntervalSince1970: 1_000))
        old.end(at: Date(timeIntervalSince1970: 2_000))
        mine.games = [old]

        var theirs = GameArchive()
        var other = makeGame(startedAt: Date(timeIntervalSince1970: 3_000))
        try other.recordDraw()
        theirs.games = [other]

        let summary = mine.merge(theirs)
        XCTAssertEqual(summary, ArchiveMergeSummary(added: 1, updated: 0))
        XCTAssertEqual(mine.games.map(\.id), [old.id, other.id])
    }

    func testMergeKeepsTheNewerCopyOfTheSameGame() throws {
        let game = makeGame(startedAt: Date(timeIntervalSince1970: 1_000))
        var longer = game
        try longer.recordDraw()
        try longer.recordDraw()

        var mine = GameArchive()
        mine.games = [game]
        var theirs = GameArchive()
        theirs.games = [longer]

        XCTAssertEqual(mine.merge(theirs), ArchiveMergeSummary(added: 0, updated: 1))
        XCTAssertEqual(mine.games.first?.records.count, 2)

        // 反过来导一次旧的，不会把新的盖掉
        var stale = GameArchive()
        stale.games = [game]
        XCTAssertTrue(mine.merge(stale).isEmpty)
        XCTAssertEqual(mine.games.first?.records.count, 2)
    }

    func testOnlyTheLatestUnfinishedGameStaysOpen() {
        var mine = GameArchive()
        mine.games = [makeGame(startedAt: Date(timeIntervalSince1970: 5_000))]
        var theirs = GameArchive()
        let earlier = makeGame(startedAt: Date(timeIntervalSince1970: 1_000))
        theirs.games = [earlier]

        mine.merge(theirs)
        XCTAssertEqual(mine.games.filter { !$0.isFinished }.count, 1)
        XCTAssertEqual(mine.activeGame?.startedAt, Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(mine.finishedGames.map(\.id), [earlier.id])
    }

    func testFrequentPlayersAreUnioned() {
        var mine = GameArchive()
        mine.remember([Player(name: "杨")])
        var theirs = GameArchive()
        theirs.remember([Player(name: "杨"), Player(name: "莉莉")])
        mine.merge(theirs)
        XCTAssertEqual(mine.frequentPlayers.map(\.name), ["杨", "莉莉"])
    }

    func testExportRoundTrips() throws {
        var archive = GameArchive()
        var game = makeGame(startedAt: Date(timeIntervalSince1970: 1_000))
        try game.recordFalseWin(offender: 2)
        archive.games = [game]
        // 存档里的时间只到秒，所以比较导出的内容
        let data = try archive.exportData()
        XCTAssertEqual(try GameArchive.decode(data).exportData(), data)
    }
}

final class SyncBookTests: XCTestCase {
    private func makeGame() -> Game {
        Game(players: ["杨", "小周", "阿乐", "老王"].map { Player(name: $0) }, startedAt: Date(timeIntervalSince1970: 1_000))
    }

    func testNewAndChangedGamesAreDirty() throws {
        var archive = GameArchive()
        var book = SyncBook()
        var game = makeGame()
        archive.games = [game]
        XCTAssertEqual(archive.dirtyGames(book).map(\.id), [game.id])

        book.synced[game.id] = GameArchive.fingerprint(game)
        XCTAssertTrue(archive.dirtyGames(book).isEmpty)

        try game.recordDraw()
        archive.upsert(game)
        XCTAssertEqual(archive.dirtyGames(book).map(\.id), [game.id])
    }

    func testRemoteReplacesAnUntouchedLocalGameEvenIfItIsShorter() throws {
        // 另一台手机撤销了一局：本机没改过，就跟着云端走
        var game = makeGame()
        try game.recordDraw()
        var archive = GameArchive()
        archive.games = [game]
        var book = SyncBook()
        book.synced[game.id] = GameArchive.fingerprint(game)

        var undone = game
        undone.undoLast()
        XCTAssertEqual(archive.applyRemote([undone], book: &book), 1)
        XCTAssertEqual(archive.games.first?.records.count, 0)
        XCTAssertTrue(archive.dirtyGames(book).isEmpty)
    }

    func testLocalEditsWinWhenNewer() throws {
        let base = makeGame()
        var archive = GameArchive()
        var book = SyncBook()
        archive.games = [base]
        book.synced[base.id] = GameArchive.fingerprint(base)

        // 另一台手机先记了一局，本机后来记了两局：本机的更新
        var theirs = base
        try theirs.recordFalseWin(offender: 1)
        Thread.sleep(forTimeInterval: 0.01)
        var mine = base
        try mine.recordDraw()
        try mine.recordDraw()
        archive.upsert(mine)

        XCTAssertEqual(archive.applyRemote([theirs], book: &book), 0)
        XCTAssertEqual(archive.games.first?.records.count, 2)
        // 本机的还要再传一次
        XCTAssertEqual(archive.dirtyGames(book).count, 1)
    }

    func testRemoteMetaUnionsPlayers() {
        var archive = GameArchive()
        archive.remember([Player(name: "杨")])
        var book = SyncBook()
        var rules = GameRules()
        rules.yuanPerPoint = 2
        archive.applyRemote(ArchiveMeta(frequentPlayers: [Player(name: "莉莉")], lastRules: rules), book: &book)
        XCTAssertEqual(archive.frequentPlayers.map(\.name), ["杨", "莉莉"])
        // 本机规则没同步过，算本机改过，不被覆盖
        XCTAssertEqual(archive.lastRules.yuanPerPoint, 1)
    }
}
