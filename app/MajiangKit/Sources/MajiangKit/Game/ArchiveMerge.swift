import Foundation

extension Game {
    /// 最后一次有动静的时间：结束时间、最后一局的时间、开局时间里最晚的。
    public var lastActivity: Date {
        [startedAt, endedAt, records.last?.date].compactMap { $0 }.max()!
    }
}

/// 导入结果：新加了几场、更新了几场。
public struct ArchiveMergeSummary: Hashable, Sendable {
    public var added = 0
    public var updated = 0

    public var isEmpty: Bool { added == 0 && updated == 0 }
}

extension GameArchive {
    /// 把另一台手机导出的记录并进来，不删本机已有的任何牌局。
    /// 同一场牌局两边都有时，留最后有动静的那份（一样新就留局数多的，再一样就留本机的）。
    /// 并完以后最多只留一场没打完的（最近开的那场），别的自动结束，免得被藏起来找不到。
    @discardableResult
    public mutating func merge(_ other: GameArchive, at date: Date = Date()) -> ArchiveMergeSummary {
        var summary = ArchiveMergeSummary()
        for game in other.games {
            if let i = games.firstIndex(where: { $0.id == game.id }) {
                let mine = games[i]
                if (game.lastActivity, game.records.count) > (mine.lastActivity, mine.records.count) {
                    games[i] = game
                    summary.updated += 1
                }
            } else {
                games.append(game)
                summary.added += 1
            }
        }
        games.sort { $0.startedAt < $1.startedAt }
        let unfinished = games.indices.filter { !games[$0].isFinished }
        for i in unfinished.dropLast() {
            games[i].end(at: games[i].lastActivity)
        }
        for player in other.frequentPlayers.reversed() where !frequentPlayers.contains(where: { $0.name == player.name }) {
            frequentPlayers.append(player)
        }
        frequentPlayers = Array(frequentPlayers.prefix(12))
        return summary
    }

    /// 导出成一个 JSON 文件的内容，格式和 App 自己的存档一样。
    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> GameArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GameArchive.self, from: data)
    }
}
