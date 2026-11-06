import SwiftUI
import UIKit
import MajiangKit

/// 记一局（14 张胡牌拍照算番）或荒庄查大叫（13 张拍照查花猪/查大叫）流程里的状态。
@MainActor
@Observable
final class RoundFlow {
    enum Step: Hashable {
        case check
    }

    enum Mode: Equatable {
        /// 14 张胡牌拍照算番。
        case win
        /// 13 张荒庄拍照查花猪 / 查大叫。
        case tingCheck(player: Int)
    }

    let game: Game
    let mode: Mode
    var steps: [Step] = []
    var showResult = false

    var winner: Int
    var winnerChosen = false
    var selfDrawn = true
    var howChosen = false
    var discarder: Int?
    /// 点杠花且家规为「点杠花算点炮」时，谁点的杠。
    var dianGangDiscarder: Int?

    var photo: UIImage?
    var concealed: [RecognizedTile] = []
    var melds: [Meld] = []
    var winningTileIndex: Int?
    var specials: Set<SpecialWin> = []
    var recognitionNotes: [String] = []
    var recognitionSource = ""

    var isRecognizing = false
    var isReviewing = false
    var recognitionError: String?
    /// 这次认牌碰到了被停用的邀请码，核对页提示重填。
    var inviteFailure: String?
    private var recognitionTask: Task<Void, Never>?

    init(game: Game, mode: Mode = .win) {
        self.game = game
        self.mode = mode
        switch mode {
        case .win:
            self.winner = game.liveRound.activePlayers.first ?? game.dealer
        case .tingCheck(let player):
            self.winner = player
            self.winnerChosen = true
        }
    }

    var isTingCheck: Bool {
        if case .tingCheck = mode { return true }
        return false
    }

    /// 当前在场可参与胡牌/点炮的玩家（血战到底已胡玩家离场）。
    var activePlayers: [Int] {
        game.rules.mode == .xuezhan ? game.liveRound.activePlayers : [0, 1, 2, 3]
    }

    func isPlayerActive(_ player: Int) -> Bool {
        activePlayers.contains(player)
    }

    // MARK: 选人

    func pickWinner(_ player: Int) {
        guard isPlayerActive(player) || isTingCheck else { return }
        winner = player
        winnerChosen = true
        if discarder == player { discarder = nil }
        if dianGangDiscarder == player { dianGangDiscarder = nil }
    }

    func pickSelfDrawn() {
        selfDrawn = true
        howChosen = true
        discarder = nil
        pruneUnavailableSpecials()
    }

    func pickDiscarder(_ player: Int) {
        guard player != winner, isPlayerActive(player) else { return }
        selfDrawn = false
        howChosen = true
        discarder = player
        dianGangDiscarder = nil
        pruneUnavailableSpecials()
    }

    // MARK: 拍照识别

    func recognize(with recognizer: any TileRecognizer) async {
        guard let photo, let data = photo.jpegData(compressionQuality: 0.85) else { return }
        recognitionTask?.cancel()
        isRecognizing = true
        isReviewing = false
        recognitionError = nil
        inviteFailure = nil

        let request = RecognitionRequest(image: data)
        let task = Task { @MainActor [weak self] in
            do {
                let result: Recognition
                if let progressive = recognizer as? ProgressiveTileRecognizer {
                    result = try await progressive.recognize(request) { [weak self] (preview: Recognition) in
                        await MainActor.run {
                            guard let self, !Task.isCancelled else { return }
                            self.load(preview)
                            self.isRecognizing = false
                            self.isReviewing = true
                            if self.steps.isEmpty { self.steps = [.check] }
                        }
                    }
                } else {
                    result = try await recognizer.recognize(request)
                }
                guard let self, !Task.isCancelled else { return }
                self.isRecognizing = false
                self.isReviewing = false
                self.load(result)
                if self.steps.isEmpty { self.steps = [.check] }
            } catch is CancellationError {
                self?.isRecognizing = false
                self?.isReviewing = false
            } catch let error as RecognitionError {
                guard let self, !Task.isCancelled else { return }
                self.isRecognizing = false
                self.isReviewing = false
                if case .inviteRejected(let message) = error {
                    self.inviteFailure = message
                } else {
                    self.recognitionError = error.message
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isRecognizing = false
                self.isReviewing = false
                self.recognitionError = "没认出来，再拍一张或手动选牌"
            }
        }
        recognitionTask = task
        await task.value
    }

    func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecognizing = false
        isReviewing = false
    }

    func load(_ recognition: Recognition) {
        if isTingCheck, recognition.melds.isEmpty, recognition.concealed.count > 13,
           let inferred = Hand.inferredTenpai(fromFlat: recognition.concealed.map(\.tile)) {
            concealed = inferred.concealed.map { RecognizedTile(tile: $0) }
            melds = inferred.melds
        } else if !isTingCheck, recognition.melds.isEmpty, recognition.concealed.count > 14,
                  let inferred = Hand.inferred(fromFlat: recognition.concealed.map(\.tile)) {
            concealed = inferred.concealed.map { RecognizedTile(tile: $0) }
            melds = inferred.melds
        } else {
            concealed = recognition.concealed
            melds = recognition.melds
        }
        recognitionNotes = recognition.notes
        recognitionSource = recognition.source
        winningTileIndex = concealed.indices.last
        if let message = recognition.notes.first(where: { $0.contains("邀请码") }) {
            inviteFailure = message
        }
        pruneUnavailableSpecials()
    }

    func startManualEntry() {
        cancelRecognition()
        photo = nil
        concealed = []
        melds = []
        winningTileIndex = nil
        specials = []
        recognitionNotes = []
        recognitionSource = "手动"
        steps = [.check]
    }

    // MARK: 改牌

    func choose(_ tile: Tile, at index: Int) {
        guard concealed.indices.contains(index) else { return }
        concealed[index] = RecognizedTile(tile: tile)
        pruneUnavailableSpecials()
    }

    func confirmTile(at index: Int) {
        guard concealed.indices.contains(index) else { return }
        concealed[index] = RecognizedTile(tile: concealed[index].tile)
    }

    func removeTile(at index: Int) {
        guard concealed.indices.contains(index) else { return }
        concealed.remove(at: index)
        if let win = winningTileIndex {
            if index == win {
                winningTileIndex = concealed.indices.last
            } else if index < win {
                winningTileIndex = win - 1
            }
        }
        pruneUnavailableSpecials()
    }

    func addTile(_ tile: Tile) {
        concealed.append(RecognizedTile(tile: tile))
        winningTileIndex = concealed.indices.last
        pruneUnavailableSpecials()
    }

    func addMeld(_ meld: Meld) {
        melds.append(meld)
        pruneUnavailableSpecials()
    }

    func removeMeld(at index: Int) {
        guard melds.indices.contains(index) else { return }
        melds.remove(at: index)
        pruneUnavailableSpecials()
    }

    func toggle(_ special: SpecialWin) {
        if specials.contains(special) {
            specials.remove(special)
        } else if special.unavailableReason(hand: hand, selfDrawn: selfDrawn) == nil {
            specials.subtract(special.conflicts)
            specials.insert(special)
        }
    }

    func apply(_ fix: HandFix) {
        if let index = fix.index {
            choose(fix.to, at: index)
        } else {
            addTile(fix.to)
        }
    }

    func applyRecommended(_ resolution: RecognitionResolution) {
        for index in resolution.removals.sorted(by: >) {
            removeTile(at: index)
        }
        for (index, tile) in resolution.recommended where concealed.indices.contains(index) {
            concealed[index] = RecognizedTile(tile: tile)
        }
        pruneUnavailableSpecials()
    }

    private func pruneUnavailableSpecials() {
        specials = specials.filter { $0.unavailableReason(hand: hand, selfDrawn: selfDrawn) == nil }
    }

    // MARK: 算番与查大叫

    var targetTileCount: Int {
        isTingCheck ? 13 : 14
    }

    var hand: Hand {
        let tiles = concealed.map(\.tile)
        let win = winningTileIndex.flatMap { tiles.indices.contains($0) ? tiles[$0] : nil }
        return Hand(melds: melds, concealed: tiles, winningTile: win)
    }

    var context: WinContext {
        var ctx = game.winContext(for: winner)
        ctx.selfDrawn = selfDrawn
        ctx.dianGangDiscarder = dianGangDiscarder
        SpecialWin.apply(specials, to: &ctx)
        return ctx
    }

    var resolution: RecognitionResolution {
        RecognitionResolver.resolve(
            Recognition(concealed: concealed, melds: melds, source: recognitionSource),
            context: context
        )
    }

    var scoring: Result<ScoringResult, ScoringError> {
        FanCalculator.score(hand, context: context)
    }

    /// 13 张查花猪/查大叫求解结果。
    var tingCheckResult: TingCheckResult {
        WinAssistant.checkTing(
            hand,
            allowMenQing: game.rules.allowMenQing,
            allowZhongZhang: game.rules.allowZhongZhang
        )
    }

    /// 13 张查叫转成流局玩家状态。
    var tingState: PlayerTingState {
        let res = tingCheckResult
        switch res.status {
        case .huaZhu:
            return .huaZhu
        case .notTing:
            return .notTing
        case .ting:
            return .ting(maxFan: res.maxFan, hand: hand)
        }
    }

    /// 杠上炮呼叫转移预览金额：点炮者在本局上一笔未转移的刮风下雨收款。
    var callTransferPreview: Int {
        guard !selfDrawn,
              let discarder,
              specials.contains(.kongPao),
              let entry = game.liveRound.kongs.last(where: { $0.kong.player == discarder && !$0.isTransferred }) else {
            return 0
        }
        return entry.gain
    }

    var tileUnitCount: Int {
        melds.count * 3 + concealed.count
    }

    /// 不能点底部主按钮的原因；nil 表示可以点。
    var blockedReason: String? {
        if isTingCheck {
            let diff = 13 - tileUnitCount
            if diff > 0 { return "查大叫需 13 张牌（还差 \(diff) 张）" }
            if diff < 0 { return "查大叫需 13 张牌（多了 \(-diff) 张）" }
            return nil
        }
        if !winnerChosen { return "上面选一下谁胡了" }
        if !howChosen { return "选一下自摸还是点炮" }
        if !selfDrawn && discarder == nil { return "选一下谁点的炮" }
        if selfDrawn && specials.contains(.kongReplacement) && game.rules.dianGangHuaRule == .asDianPao && dianGangDiscarder == nil {
            return "点杠花算点炮：选一下谁点的杠"
        }
        switch scoring {
        case .success(let result):
            if !result.meetsMinimum(game.rules.minimumFan) {
                return "还差 \(game.rules.minimumFan - result.totalFan) 番才够起胡"
            }
            return nil
        case .failure(let error):
            switch error {
            case .wrongTileCount:
                let diff = 14 - tileUnitCount
                return diff > 0 ? "还差 \(diff) 张牌" : "多了 \(-diff) 张牌"
            case .tileMoreThanFour:
                return "同一种牌超过了 4 张"
            case .missingSuitRequired:
                return "万筒条三门俱全（花猪），川麻必须缺一门才能胡"
            case .notAWin:
                return "这副牌还没凑成胡牌"
            }
        }
    }

    var winRecord: WinRecord? {
        guard blockedReason == nil, case .success(let result) = scoring else { return nil }
        return WinRecord(
            winner: winner,
            discarder: selfDrawn ? nil : discarder,
            hand: hand,
            context: context,
            result: result,
            callTransferAmount: callTransferPreview
        )
    }

    var previewDeltas: [Int]? {
        guard let win = winRecord else { return nil }
        return Payment.winDeltas(
            win: win,
            activePlayers: game.liveRound.activePlayers,
            dealer: game.dealer,
            rules: game.rules
        )
    }
}
