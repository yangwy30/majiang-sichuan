import Foundation

/// 所有牌局和常用牌友，存成一个 JSON 文件。
public struct GameArchive: Codable, Hashable, Sendable {
    /// 存档格式版本。改了不兼容的格式时加 1，并在 init(from:) 里迁移旧版本。
    public static let currentVersion = 1

    public var version = GameArchive.currentVersion
    public var games: [Game] = []
    public var frequentPlayers: [Player] = []
    public var lastRules = GameRules()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case version, games, frequentPlayers, lastRules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        games = try c.decodeIfPresent([Game].self, forKey: .games) ?? []
        frequentPlayers = try c.decodeIfPresent([Player].self, forKey: .frequentPlayers) ?? []
        lastRules = try c.decodeIfPresent(GameRules.self, forKey: .lastRules) ?? GameRules()
    }

    public var activeGame: Game? { games.last { !$0.isFinished } }

    public var finishedGames: [Game] {
        games.filter(\.isFinished).sorted { $0.startedAt > $1.startedAt }
    }

    public mutating func upsert(_ game: Game) {
        if let i = games.firstIndex(where: { $0.id == game.id }) {
            games[i] = game
        } else {
            games.append(game)
        }
    }

    /// 这 4 个人最近一场用的规则（不管座位顺序）。没一起打过就是 nil。
    /// 直接从历史牌局里找，不用另存，换手机同步过来也一样。
    public func lastRules(forPlayers names: [String]) -> GameRules? {
        let wanted = Set(names)
        guard wanted.count == 4 else { return nil }
        return games
            .filter { Set($0.players.map(\.name)) == wanted }
            .max { $0.startedAt < $1.startedAt }?
            .rules
    }

    /// 上一场里「我」的名字，开新局时预先填在第一行。
    public var lastMeName: String? {
        games.max { $0.startedAt < $1.startedAt }.map { $0.players[$0.me].name }
    }

    /// 记住用过的名字，新建牌局时可以一点就加。
    public mutating func remember(_ players: [Player]) {
        for player in players where !player.name.isEmpty {
            frequentPlayers.removeAll { $0.name == player.name }
            frequentPlayers.insert(player, at: 0)
        }
        frequentPlayers = Array(frequentPlayers.prefix(12))
    }

    /// 开新局：上一场没点「结束」的牌局自动结束，这样它会出现在历史里，不会找不到。
    @discardableResult
    public mutating func start(_ game: Game, at date: Date = Date()) -> Game {
        for i in games.indices where !games[i].isFinished {
            games[i].end(at: date)
        }
        games.append(game)
        return game
    }

    /// 读存档；读不出来时把原文件改名备份（不覆盖、不删除），返回空存档和备份位置。
    /// 这样之后的保存不会把读不出来的历史记录覆盖掉。
    public static func loadOrRecover(from url: URL, now: Date = Date()) -> (archive: GameArchive, backup: URL?, error: Error?) {
        do {
            return (try load(from: url), nil, nil)
        } catch {
            let stamp = Int(now.timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("archive-unreadable-\(stamp).json")
            do {
                try FileManager.default.moveItem(at: url, to: backup)
                return (GameArchive(), backup, error)
            } catch {
                return (GameArchive(), nil, error)
            }
        }
    }

    public static func load(from url: URL) throws -> GameArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return GameArchive() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GameArchive.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
