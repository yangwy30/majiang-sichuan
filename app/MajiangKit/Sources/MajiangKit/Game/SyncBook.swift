import Foundation

/// iCloud 同步的记账本：每场牌局上次和云端一致时的指纹。和这个指纹不一样，就说明本机改过、要上传。
/// 只管「该传哪些、云端来的该不该收」，真正读写 CloudKit 在 App 里。
public struct SyncBook: Codable, Hashable, Sendable {
    public var synced: [UUID: UInt64] = [:]
    /// 常用牌友和上次规则的指纹。
    public var meta: UInt64?

    public init() {}

    public func isDirty(_ game: Game) -> Bool {
        synced[game.id] != GameArchive.fingerprint(game)
    }
}

/// 云端存的除牌局以外的东西：常用牌友、上次用的规则。
public struct ArchiveMeta: Codable, Hashable, Sendable {
    public var frequentPlayers: [Player]
    public var lastRules: GameRules

    public init(frequentPlayers: [Player], lastRules: GameRules) {
        self.frequentPlayers = frequentPlayers
        self.lastRules = lastRules
    }
}

extension GameArchive {
    /// 一场牌局的内容指纹（FNV-1a，跨启动稳定）。
    public static func fingerprint<T: Encodable>(_ value: T) -> UInt64 {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    public var meta: ArchiveMeta { ArchiveMeta(frequentPlayers: frequentPlayers, lastRules: lastRules) }

    /// 本机改过、还没传上去的牌局。
    public func dirtyGames(_ book: SyncBook) -> [Game] {
        games.filter(book.isDirty)
    }

    /// 收下云端发来的牌局。本机这场没改过就直接用云端的；两边都改过时按 `merge` 的规则留新的那份，
    /// 本机的赢了就继续算没同步，下次会传上去。返回本机实际变了的场数。
    @discardableResult
    public mutating func applyRemote(_ remote: [Game], book: inout SyncBook) -> Int {
        var changed = 0
        for game in remote {
            let print = Self.fingerprint(game)
            if let i = games.firstIndex(where: { $0.id == game.id }) {
                let mine = games[i]
                let keepMine = book.isDirty(mine)
                    && (mine.lastActivity, mine.records.count) >= (game.lastActivity, game.records.count)
                if !keepMine && mine != game {
                    games[i] = game
                    changed += 1
                }
            } else {
                games.append(game)
                changed += 1
            }
            book.synced[game.id] = print
        }
        if changed > 0 {
            // 和导入一样：排好序，只留最近开的那场没打完
            merge(GameArchive())
        }
        return changed
    }

    /// 收下云端的常用牌友和规则：牌友取并集，规则本机没改过才用云端的。
    public mutating func applyRemote(_ remote: ArchiveMeta, book: inout SyncBook) {
        // 从没同步过时，本机还是默认值就算没改过（新手机第一次同步直接用云端的）
        let localDirty = book.meta.map { $0 != Self.fingerprint(meta) }
            ?? (meta != ArchiveMeta(frequentPlayers: [], lastRules: GameRules()))
        var other = GameArchive()
        other.frequentPlayers = remote.frequentPlayers
        merge(other)
        if !localDirty { lastRules = remote.lastRules }
        book.meta = Self.fingerprint(remote)
    }
}
