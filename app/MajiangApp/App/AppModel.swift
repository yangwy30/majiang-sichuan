import SwiftUI
import MajiangKit

/// 只有一条主线：首页 → 开局 → 牌桌（也是账本）→ 结算。记一局是从牌桌全屏弹出的。
enum Route: Hashable {
    case newGame
    case table(UUID)
    /// 账本里点开的一局和牌：牌局编号、那一局的编号。
    case hand(UUID, UUID)
    case settle(UUID)
}

/// 识别用哪一路。默认「自动」：有什么用什么，什么都没有才用演示数据。只在开发版的设置里能改。
enum RecognitionMode: String, CaseIterable, Identifiable {
    case auto, demo, gemini, onDevice, dual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "自动（推荐）"
        case .demo: "演示数据"
        case .gemini: "Gemini"
        case .onDevice: "只用端侧模型"
        case .dual: "端侧 + Gemini 双读"
        }
    }

    var usesOnDeviceModel: Bool { self == .onDevice || self == .dual }

    /// 自动时实际用哪一路：Key 和端侧模型都有就双读，只有一样就用那一样，都没有才是演示数据。
    static func resolveAuto(hasKey: Bool, hasModel: Bool) -> RecognitionMode {
        switch (hasKey, hasModel) {
        case (true, true): .dual
        case (true, false): .gemini
        case (false, true): .onDevice
        case (false, false): .demo
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var archive: GameArchive
    var path: [Route] = []
    var loadError: String?

    var recognitionMode: RecognitionMode {
        didSet { UserDefaults.standard.set(recognitionMode.rawValue, forKey: "recognitionMode") }
    }

    /// 后端代理地址（server/ 里的 Cloudflare Worker）；为空时直接调 Google（开发用）。
    /// 正式版默认走代理；开发版默认用自带的 Key 直连，想试代理就在设置里点「用我们的服务器」。
    var proxyURL: String {
        didSet { UserDefaults.standard.set(proxyURL, forKey: "proxyURL") }
    }

    /// 中转站地址。1.0 用的是 workers.dev，中国大陆大多连不上，1.0.1 起换成自己的域名（同一个 Worker，旧地址也还在）。
    static let defaultProxyURL = "https://majiang.acrossus.app/recognize"
    static let legacyProxyURL = "https://majiang-relay.yangwang9710.workers.dev/recognize"

    /// AI 认牌的邀请码（中转站确认过才存）。走中转站时没码就不调 Gemini，只用端侧认牌。
    private(set) var inviteCode: String? = InviteKeychain.read()
    /// 认牌时码被中转站拒了（停用了之类），说一句为什么，邀请码页上显示。
    var inviteNotice: String?

    private let archiveURL: URL
    /// iCloud 同步；截图模式下不同步。
    let cloud: CloudSync
    /// 演示识别只建一次，这样每次拍照会轮到下一手示例牌。
    private let demoRecognizer = MockRecognizer()
    /// 端侧模型加载一次就留着（外层 nil = 还没加载，内层 nil = 没装）。
    @ObservationIgnored private var loadedDetector: TileDetecting??

    /// 截图模式停在哪一页（见 DemoData）；正式版永远是 nil。
    let demoScreen = DemoScreen.current

    init(archiveURL: URL? = nil) {
        var url = archiveURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("majiang", isDirectory: true)
            .appendingPathComponent("archive.json")
        #if DEBUG
        if let screen = DemoScreen.current {
            // 截图用的假数据放临时目录，每次启动重新生成
            url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-archive.json")
            try? FileManager.default.removeItem(at: url)
            if screen != .emptyHome {
                let archive = DemoData.archive()
                try? archive.save(to: url)
                DemoData.preparePhotos(archive)
            }
        }
        #endif
        // 读不出来时原文件会被改名备份，之后保存不会覆盖掉旧记录
        let (loaded, backup, failure) = GameArchive.loadOrRecover(from: url)
        var error: String?
        if let failure {
            error = "读取牌局记录失败：\(failure.localizedDescription)"
            if let backup { error! += "。原文件已备份为 \(backup.lastPathComponent)" }
        }
        self.archiveURL = url
        self.cloud = CloudSync(stateURL: url.deletingLastPathComponent().appendingPathComponent("cloud-state.json"))
        if DemoScreen.current != nil { cloud.enabled = false }
        self.archive = loaded
        #if DEBUG
        if DemoScreen.current == nil { GeminiKeychain.importBundledDevKey() }
        #endif
        self.recognitionMode = RecognitionMode(rawValue: UserDefaults.standard.string(forKey: "recognitionMode") ?? "") ?? .auto
        #if DEBUG
        self.proxyURL = UserDefaults.standard.string(forKey: "proxyURL") ?? ""
        #else
        self.proxyURL = UserDefaults.standard.string(forKey: "proxyURL") ?? Self.defaultProxyURL
        #endif
        self.loadError = error
        // 存过旧的 workers.dev 地址（在开发设置里点过「用我们的服务器」）的，换成新地址
        if proxyURL == Self.legacyProxyURL { proxyURL = Self.defaultProxyURL }
        // 有没打完的牌局时，打开 App 直接进牌桌
        if let active = loaded.activeGame { path = [.table(active.id)] }
        switch demoScreen {
        case .home, .emptyHome, .backup, .invite, .more: path = []
        case .newGame, .houseRules, .rulePicker: path = [.newGame]
        case .settle: path = loaded.finishedGames.first.map { [.settle($0.id)] } ?? []
        case .handDetail, .handPhoto, .handDiscard:
            let i = demoScreen == .handDiscard ? 1 : 0
            if let game = loaded.activeGame, game.records.indices.contains(i) {
                path = [.table(game.id), .hand(game.id, game.records[i].id)]
            }
        default: break
        }
        // 账本里已经没有的局（别的设备删了、同步过来），照片也删掉。读档失败时不动，免得把照片全清了
        if failure == nil && demoScreen == nil {
            HandPhotos.prune(keeping: Set(loaded.games.flatMap { $0.records.map(\.id) }))
        }
    }

    // MARK: 牌局

    func game(_ id: UUID) -> Game? { archive.games.first { $0.id == id } }

    func update(_ game: Game) {
        archive.upsert(game)
        save()
    }

    /// 已经记过 3 手和牌：页面上教怎么用的说明句就收起来，只留真要做判断时的提示。
    /// 截图（demo）时按新手的样子显示。
    var isSeasoned: Bool {
        guard demoScreen == nil else { return false }
        var wins = 0
        for game in archive.games {
            for record in game.records {
                if case .win = record.outcome { wins += 1 }
            }
        }
        return wins >= 3
    }

    @discardableResult
    func startGame(players: [Player], me: Int = 0, rules: GameRules) -> Game {
        let game = archive.start(Game(players: players, me: me, rules: rules))
        archive.remember(players)
        archive.lastRules = rules
        save()
        return game
    }

    /// 存到本机，再排一次 iCloud 同步。
    func save() {
        saveLocally()
        cloud.scheduleSync(self)
    }

    /// 只存本机（收到 iCloud 的改动时用，不用再传回去）。
    func saveLocally() {
        do {
            try archive.save(to: archiveURL)
        } catch {
            loadError = "保存失败：\(error.localizedDescription)"
        }
    }

    func syncNow() async {
        guard demoScreen == nil else { return }
        await cloud.sync(self)
    }

    // MARK: 导出导入（不用 iCloud 时换手机）

    /// 把全部记录写成一个文件，用来存到「文件」或隔空投送。
    func exportFile() throws -> URL {
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.omitted))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("拍照算番-全部牌局-\(stamp).json")
        try archive.exportData().write(to: url, options: .atomic)
        return url
    }

    /// 并入另一台手机导出的文件，只加不删。
    func importFile(_ url: URL) throws -> ArchiveMergeSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let other = try GameArchive.decode(Data(contentsOf: url))
        let summary = archive.merge(other)
        if !summary.isEmpty || !other.frequentPlayers.isEmpty { save() }
        return summary
    }

    // MARK: 识别

    /// 这次拍照实际走哪一路（「自动」在这里落到具体的一路）。
    var effectiveRecognitionMode: RecognitionMode {
        guard recognitionMode == .auto else { return recognitionMode }
        return .resolveAuto(hasKey: canUseGemini, hasModel: Self.onDeviceModelURL != nil)
    }

    /// 走中转站（https 地址），而不是开发版直连 Google。
    var usesProxy: Bool { URL(string: proxyURL)?.scheme == "https" }

    /// 能不能调 Gemini：开发版有 Key 直连；走中转站要有邀请码。
    var canUseGemini: Bool { usesProxy ? inviteCode != nil : GeminiKeychain.hasKey }

    /// 拍照页要不要提示「AI 认牌需邀请码」：走中转站、还没码、识别方式是自动。
    var needsInvite: Bool { demoScreen == nil && recognitionMode == .auto && usesProxy && inviteCode == nil }

    // MARK: 邀请码

    /// 问中转站码对不对，对了就存下。失败时返回给用户看的一句话。
    func redeemInvite(_ input: String) async -> String? {
        guard let proxy = URL(string: proxyURL), usesProxy else { return "还没连上我们的服务器" }
        do {
            let redemption = try await InviteCode.redeem(input, proxy: proxy, deviceID: DeviceID.current)
            InviteKeychain.save(redemption.code)
            inviteCode = redemption.code
            inviteNotice = nil
            return nil
        } catch {
            return (error as? RecognitionError)?.message ?? error.localizedDescription
        }
    }

    func removeInvite(notice: String? = nil) {
        InviteKeychain.save(nil)
        inviteCode = nil
        inviteNotice = notice
    }

    func makeRecognizer() -> TileRecognizer {
        if demoScreen != nil { return demoRecognizer }
        switch effectiveRecognitionMode {
        case .auto, .demo:
            return demoRecognizer
        case .gemini:
            return checkedGemini()
        case .onDevice:
            return OnDeviceRecognizer(detector: onDeviceDetector)
        case .dual:
            return DualReadRecognizer(primary: OnDeviceRecognizer(detector: onDeviceDetector),
                                      secondary: checkedGemini())
        }
    }

    // MARK: 端侧模型

    /// 端侧模型在 App 包里的位置（Xcode 把 Resources/Models/MahjongTileDetector.mlpackage 编译成 .mlmodelc）。
    /// 模型不进仓库，没放的话就是 nil，双读只剩 Gemini 一路。见 app/README.md。
    nonisolated static var onDeviceModelURL: URL? {
        Bundle.main.url(forResource: "MahjongTileDetector", withExtension: "mlmodelc")
    }

    private var onDeviceDetector: TileDetecting? {
        if let loaded = loadedDetector { return loaded }
        let detector = Self.loadDetector()
        loadedDetector = .some(detector)
        return detector
    }

    /// 打开拍照页时先在后台把模型加载好，按快门时不用等。
    func preloadOnDeviceModel() async {
        guard loadedDetector == nil, effectiveRecognitionMode.usesOnDeviceModel else { return }
        let detector = await Task.detached(priority: .userInitiated) { Self.loadDetector() }.value
        if loadedDetector == nil { loadedDetector = .some(detector) }
    }

    nonisolated private static func loadDetector() -> TileDetecting? {
        guard let url = onDeviceModelURL else { return nil }
        return try? CoreMLTileDetector(compiledModelAt: url)
    }

    /// Gemini + 规则校验；中转站说码有问题时清掉码，下次拍照页提示重新输入。
    private func checkedGemini() -> TileRecognizer {
        InviteCheckedRecognizer(base: RuleCheckedRecognizer(base: gemini())) { [weak self] in
            await MainActor.run {
                self?.removeInvite(notice: "上次的邀请码不能用了：中转站说它停用了或者不对，找给你码的人再要一个")
            }
        }
    }

    private func gemini() -> GeminiRecognizer {
        let endpoint: GeminiConfiguration.Endpoint
        if let url = URL(string: proxyURL), url.scheme == "https" {
            endpoint = .proxy(url: url, deviceID: DeviceID.current, inviteCode: inviteCode)
        } else {
            endpoint = .direct(GeminiKeychain())
        }
        let sheet = ReferenceSheet.jpegData().map { (data: $0, mimeType: "image/jpeg") }
        return GeminiRecognizer(configuration: GeminiConfiguration(endpoint: endpoint, referenceSheet: sheet))
    }
}
