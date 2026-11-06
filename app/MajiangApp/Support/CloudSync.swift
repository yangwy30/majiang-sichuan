import CloudKit
import Foundation
import MajiangKit
import os

/// iCloud 同步：牌局存在用户自己 iCloud 的私有库里，每场一条记录（内容就是存档里那场的 JSON）。
/// 打开 App、回到前台、每次保存后同步一次：先收云端改过的，再传本机改过的。
/// 什么该传、云端来的收不收由 MajiangKit 的 `SyncBook` 决定，这里只管读写 CloudKit。
@MainActor
@Observable
final class CloudSync {
    enum Status: Equatable {
        /// 设置里关掉了。
        case off
        /// 这台手机没登录 iCloud，或者 iCloud 里关了这个 App。
        case unavailable(String)
        case syncing
        case synced(Date)
        case failed(String)
    }

    static let containerID = "iCloud.com.yangwy30.majiang"

    private(set) var status: Status = .off

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "iCloudSync")
            if !enabled { status = .off }
        }
    }

    private let stateURL: URL
    private var state: State
    private var running = false
    private var again = false
    private var debounce: Task<Void, Never>?

    // 用到时才建：@Observable 不跟踪它，lazy 也不能引用 Self。
    @ObservationIgnored private lazy var database = CKContainer(identifier: CloudSync.containerID).privateCloudDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "Majiang", ownerName: CKCurrentUserDefaultName)

    /// 存在本机的同步进度：上次同步到哪（CloudKit 的 change token），每场牌局上次同步时的指纹。
    private struct State: Codable {
        var book = SyncBook()
        var zoneReady = false
        var changeToken: Data?
    }

    init(stateURL: URL) {
        self.stateURL = stateURL
        self.state = (try? JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))) ?? State()
        self.enabled = UserDefaults.standard.object(forKey: "iCloudSync") as? Bool ?? true
    }

    /// 保存后调用：等一会儿再同步，连着记几局只传一次。
    func scheduleSync(_ model: AppModel) {
        guard enabled else { return }
        debounce?.cancel()
        debounce = Task { [weak model] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let model else { return }
            await self.sync(model)
        }
    }

    func sync(_ model: AppModel) async {
        guard enabled else { return }
        if running {
            again = true
            return
        }
        running = true
        defer { running = false }
        repeat {
            again = false
            await syncOnce(model)
        } while again && enabled
    }

    private func syncOnce(_ model: AppModel) async {
        do {
            let container = CKContainer(identifier: Self.containerID)
            switch try await container.accountStatus() {
            case .available: break
            case .noAccount:
                status = .unavailable("这台手机没登录 iCloud，登录后会自动同步。")
                return
            case .restricted:
                status = .unavailable("这台手机的 iCloud 被限制了（比如家长控制）。")
                return
            default:
                status = .unavailable("现在连不上 iCloud，稍后会再试。")
                return
            }
            status = .syncing
            try await prepareZone()
            try await pull(into: model)
            try await push(from: model)
            status = .synced(Date())
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // 云端的数据被删了（比如在设置里清了 iCloud 数据）：重建，把本机的全部重新传上去
            state = State()
            persist()
            again = true
        } catch let error as CKError where error.code == .notAuthenticated {
            status = .unavailable("这台手机没登录 iCloud，登录后会自动同步。")
        } catch let error as CKError where error.code == .quotaExceeded {
            status = .failed("iCloud 空间满了，牌局只存在这台手机上。")
        } catch let error as CKError where [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited].contains(error.code) {
            status = .failed("没有网络，联网后会自动同步。")
        } catch {
            // 原始错误只记日志，界面上不出现英文报错
            Self.log.error("iCloud 同步失败：\(String(describing: error), privacy: .public)")
            status = .failed("iCloud 同步暂时没成功，牌局都存在这台手机上，不会丢。稍后会自动再试。")
        }
    }

    private static let log = Logger(subsystem: "com.yangwy30.majiang", category: "CloudSync")

    private func prepareZone() async throws {
        guard !state.zoneReady else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        state.zoneReady = true
        persist()
    }

    // MARK: 收

    private func pull(into model: AppModel) async throws {
        var token = state.changeToken.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        var games: [Game] = []
        var meta: ArchiveMeta?
        while true {
            let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, Error>],
                          deletions: [CKDatabase.RecordZoneChange.Deletion],
                          changeToken: CKServerChangeToken, moreComing: Bool)
            do {
                changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            } catch let error as CKError where error.code == .changeTokenExpired {
                token = nil
                continue
            }
            for case .success(let modification) in changes.modificationResultsByID.values {
                let record = modification.record
                guard let data = record["json"] as? Data else { continue }
                switch record.recordType {
                case "Game":
                    if let game = try? Self.decoder.decode(Game.self, from: data) { games.append(game) }
                case "Meta":
                    meta = try? Self.decoder.decode(ArchiveMeta.self, from: data)
                default:
                    break
                }
            }
            token = changes.changeToken
            if !changes.moreComing { break }
        }

        var book = state.book
        var changed = model.archive.applyRemote(games, book: &book) > 0
        if let meta {
            let before = model.archive.meta
            model.archive.applyRemote(meta, book: &book)
            changed = changed || model.archive.meta != before
        }
        if changed { model.saveLocally() }
        state.book = book
        state.changeToken = token.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        persist()
    }

    // MARK: 传

    private func push(from model: AppModel) async throws {
        let archive = model.archive
        let dirty = archive.dirtyGames(state.book)
        let meta = archive.meta
        let metaDirty = state.book.meta != GameArchive.fingerprint(meta)
        guard !dirty.isEmpty || metaDirty else { return }

        var records: [(CKRecord, () -> Void)] = []
        for game in dirty {
            let record = CKRecord(recordType: "Game", recordID: CKRecord.ID(recordName: game.id.uuidString, zoneID: zoneID))
            record["json"] = try Self.encoder.encode(game)
            record["startedAt"] = game.startedAt
            let print = GameArchive.fingerprint(game)
            records.append((record, { [unowned self] in state.book.synced[game.id] = print }))
        }
        if metaDirty {
            let record = CKRecord(recordType: "Meta", recordID: CKRecord.ID(recordName: "meta", zoneID: zoneID))
            record["json"] = try Self.encoder.encode(meta)
            let print = GameArchive.fingerprint(meta)
            records.append((record, { [unowned self] in state.book.meta = print }))
        }

        // 一次最多传 400 条
        for start in stride(from: 0, to: records.count, by: 200) {
            let chunk = records[start..<min(start + 200, records.count)]
            // 刚收过云端的，直接整条覆盖，不比较版本
            let results = try await database.modifyRecords(saving: chunk.map(\.0), deleting: [],
                                                           savePolicy: .allKeys, atomically: false).saveResults
            var firstError: Error?
            for (record, markSynced) in chunk {
                switch results[record.recordID] {
                case .success: markSynced()
                case .failure(let error): firstError = firstError ?? error
                case nil: break
                }
            }
            persist()
            if let firstError { throw firstError }
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        } catch {
            // 同步进度丢了只会让下次多传一遍，不影响牌局
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
