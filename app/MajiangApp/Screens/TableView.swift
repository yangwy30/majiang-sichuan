import SwiftUI
import MajiangKit

/// 牌桌，也是账本：上面按座位画四个人，往下滚是每一笔记录。
struct TableView: View {
    @Environment(AppModel.self) private var model
    let gameID: UUID

    @State private var recording = false
    @State private var showKong = false
    @State private var showDraw = false
    @State private var manualScoring = false
    @State private var showGuide = false
    @State private var editingRules = false
    @State private var confirmEnd = false
    @State private var pickingFalseWin = false
    /// 点开要改的那一笔。
    @State private var editing: EditTarget?
    @State private var recordError: String?
    /// 刚记下的一笔，底部显示 8 秒「撤销」（牌桌上大家还在说话，5 秒常常反应不过来）。
    @State private var justRecorded: HandRecord?
    @State private var undoTimer: Task<Void, Never>?
    /// 这一页有多高：矮屏方桌画小一点。
    @State private var pageHeight: CGFloat = 0
    /// 点了撤销就加一，触发一下轻震。
    @State private var undoCount = 0

    var body: some View {
        if let game = model.game(gameID) {
            content(game)
        } else {
            ContentUnavailableView("找不到这场牌局", systemImage: "questionmark")
        }
    }

    /// 从结算页点「看每一局」进来的回结算，平时回首页。
    private var backTitle: String {
        if model.path.count >= 2, case .settle = model.path[model.path.count - 2] { return "结算" }
        return "首页"
    }

    private func winButtonTitle(_ game: Game) -> String {
        if game.rules.mode == .xuezhan {
            let count = game.liveRound.wonPlayers.count
            if count == 1 { return "又有人胡了（二胡）" }
            if count == 2 { return "又有人胡了（三胡）" }
        }
        return "有人胡了"
    }

    private func drawButtonTitle(_ game: Game) -> String {
        if !game.liveRound.events.isEmpty {
            return "牌摸完了（流局 / 退税）"
        }
        return "这局没人胡"
    }

    private func undoTitle(_ record: HandRecord, in game: Game) -> String {
        switch record.outcome {
        case .kong(let kong):
            return "已记下 · \(game.players[kong.player].name)\(kong.kind.shortName)"
        case .win(let win):
            return "已记下 · \(game.players[win.winner].name)胡牌"
        default:
            return "已记下第 \(record.handIndex + 1) 局"
        }
    }

    private func content(_ game: Game) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 家规跟标准血战不一样时才露一行，点开能改
                if let badge = game.rules.houseRuleBadge {
                    Button { editingRules = true } label: {
                        Text(badge + " ›")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.gray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.lineSoft, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }

                // 矮屏（SE、mini）方桌小一圈，账本多露出一行
                TableDiagram(game: game, compact: pageHeight > 0 && pageHeight < 700)
                    .padding(.top, 10)

                HStack(alignment: .firstTextBaseline) {
                    Text("账本").font(.system(size: 14, weight: .medium))
                    Spacer()
                    Text(game.isFinished ? "打了 \(game.currentHandIndex) 局"
                         : "第 \(min(game.currentHandIndex + 1, game.rules.totalHands)) / \(game.rules.totalHands) 局")
                        .font(.system(size: 14))
                }
                .foregroundStyle(Theme.gray)
                .padding(.top, 26)
                .padding(.bottom, 6)
                Hairline()

                if game.records.isEmpty {
                    Text("还没有记录。有人胡了点下面黑按钮，中途开杠点「刮风下雨」。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.vertical, 14)
                }
                ForEach(Array(game.records.enumerated().reversed()), id: \.element.id) { index, record in
                    Button {
                        open(record, number: index + 1)
                    } label: {
                        RecordRow(number: index + 1, record: record, game: game)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(record.isWin ? "点一下看这一把怎么胡的" : "点一下可以改或删掉这一条")
                }
                if !game.records.isEmpty && !model.isSeasoned {
                    Text("点一条记录，看那把怎么胡的；记错了也在里面改。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 24)
        }
        .bottomBar {
            if let record = justRecorded {
                UndoBar(text: undoTitle(record, in: game)) { undo(record) }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if game.isFinished {
                Button("看结算") { settle(game) }
                    .buttonStyle(.primary)
            } else {
                Button(winButtonTitle(game)) { recording = true }
                    .buttonStyle(.primary)
                HStack(spacing: 18) {
                    Button("刮风下雨") { showKong = true }
                        .buttonStyle(.text)
                    Text("·")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.faint)
                    Button(drawButtonTitle(game)) { showDraw = true }
                        .buttonStyle(.text)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
        .page()
        .sensoryFeedback(.success, trigger: justRecorded?.id) { _, new in new != nil }
        .sensoryFeedback(.impact(weight: .light), trigger: undoCount)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            NavBack(backTitle) { model.path.removeLast() }
            NavTool {
                Button("发到群") { ShareSheet.share(game) }
                    .accessibilityLabel("把账本发到群里")
            }
            NavTool {
                Menu {
                    if !game.isFinished {
                        Button("有人诈胡了") { pickingFalseWin = true }
                    }
                    Button("直接改分") { manualScoring = true }
                    Button("这场的规则") { editingRules = true }
                    Button("规则和番种说明") { showGuide = true }
                    Divider()
                    if !game.isFinished {
                        Button("结束牌局", role: .destructive) { confirmEnd = true }
                    }
                } label: {
                    Text("更多")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.gray)
                        .fixedSize()
                        .frame(minHeight: 44)
                }
            }
        }
        .confirmationDialog("谁诈胡了？", isPresented: $pickingFalseWin, titleVisibility: .visible) {
            ForEach(0..<4, id: \.self) { i in
                Button(game.players[i].name) { record { try $0.recordFalseWin(offender: i) } }
            }
        } message: {
            Text("推倒了却没缺一门或凑不成胡牌：赔在场每家各 \(game.rules.falseWinPenalty) 分，这一局接着打。")
        }
        .sheet(item: $editing) { target in
            EditHandSheet(game: game, record: target.record, number: target.number) { outcome in
                edit { try $0.replace(target.record.id, with: outcome) }
            } onDelete: {
                edit { $0.remove(target.record.id) }
                HandPhotos.delete(target.record.id)
            }
        }
        .alert("结束这场牌局？", isPresented: $confirmEnd) {
            Button("结束", role: .destructive) { settle(game) }
            Button("再打会儿", role: .cancel) {}
        } message: {
            Text("结束后就不能再记了，会算出谁该给谁转多少。")
        }
        .fullScreenCover(isPresented: $recording) {
            RoundFlowView(game: game, mode: .win, demo: model.demoScreen) { outcome, photo in
                switch outcome {
                case .win(let win):
                    if let saved = record({ try $0.recordWin(win) }), let photo { HandPhotos.save(photo, for: saved.id) }
                case .falseWin(let offender):
                    record { try $0.recordFalseWin(offender: offender) }
                default:
                    break
                }
            }
        }
        .sheet(isPresented: $showKong) {
            KongSheet(game: game) { kong in
                record { try $0.recordKong(kong) }
            }
        }
        .sheet(isPresented: $showDraw) {
            DrawSheet(game: game) { states in
                record { try $0.recordDrawSettlement(states: states) }
            } onPlainDraw: {
                record { try $0.recordDraw() }
            }
        }
        .sheet(isPresented: $manualScoring) {
            ManualScoreView(game: game) { deltas, note in
                record { try $0.recordManual(deltas: deltas, note: note) }
            }
        }
        .sheet(isPresented: $showGuide) { RulesGuideView() }
        .sheet(isPresented: $editingRules) {
            GameRulesSheet(game: game, draft: demoRulesDraft(game)) { rules in
                edit { try $0.changeRules(rules) }
            }
        }
        .onAppear {
            if model.demoScreen == .table { justRecorded = game.records.last }
            if model.demoScreen == .editHand, game.records.count > 1 {
                editing = EditTarget(record: game.records[1], number: 2)
            }
            if model.demoScreen?.opensRound == true { recording = true }
            if model.demoScreen == .gameRules { editingRules = true }
        }
        .alert("没有记上", isPresented: Binding(get: { recordError != nil }, set: { if !$0 { recordError = nil } })) {
            Button("好") { recordError = nil }
        } message: {
            Text(recordError ?? "")
        }
    }

    private func demoRulesDraft(_ game: Game) -> GameRules? {
        guard model.demoScreen == .gameRules else { return nil }
        var rules = game.rules
        rules.basePoints = 5
        return rules
    }

    @discardableResult
    private func record(_ change: (inout Game) throws -> HandRecord) -> HandRecord? {
        guard var updated = model.game(gameID) else { return nil }
        do {
            let record = try change(&updated)
            model.update(updated)
            showUndo(for: record)
            return record
        } catch let error as GameError {
            recordError = error.message
        } catch {
            recordError = error.localizedDescription
        }
        return nil
    }

    private func open(_ record: HandRecord, number: Int) {
        guard record.isWin else {
            editing = EditTarget(record: record, number: number)
            return
        }
        undoTimer?.cancel()
        justRecorded = nil
        model.path.append(.hand(gameID, record.id))
    }

    private func showUndo(for record: HandRecord) {
        undoTimer?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { justRecorded = record }
        undoTimer = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { justRecorded = nil }
        }
    }

    private func edit(_ change: (inout Game) throws -> Void) {
        guard var updated = model.game(gameID) else { return }
        do {
            try change(&updated)
            model.update(updated)
            if let record = justRecorded, updated.records.last?.id != record.id || updated.records.last != record {
                undoTimer?.cancel()
                withAnimation(.easeIn(duration: 0.2)) { justRecorded = nil }
            }
        } catch let error as GameError {
            recordError = error.message
        } catch {
            recordError = error.localizedDescription
        }
    }

    private func undo(_ record: HandRecord) {
        undoTimer?.cancel()
        guard var updated = model.game(gameID), updated.records.last?.id == record.id else { return }
        updated.undoLast()
        model.update(updated)
        undoCount += 1
        HandPhotos.delete(record.id)
        withAnimation(.easeIn(duration: 0.2)) { justRecorded = nil }
    }

    private func settle(_ game: Game) {
        var updated = game
        if updated.endedAt == nil { updated.end() }
        model.update(updated)
        model.path = [.settle(game.id)]
    }
}

private struct EditTarget: Identifiable {
    var record: HandRecord
    var number: Int
    var id: UUID { record.id }
}

// MARK: - 牌桌图

/// 方桌：自己总在最下面，右手边是下家、对面是对家、左手边是上家。
private struct TableDiagram: View {
    var game: Game
    var compact = false

    private var hand: Int { min(game.currentHandIndex, game.rules.totalHands - 1) }

    var body: some View {
        let seating = game.seating(ofRound: game.roundIndex(ofHand: hand))
        let me = game.position(of: game.me, inHand: hand)
        let at = { (offset: Int) in seating[(me + offset) % 4] }
        ZStack {
            VStack(spacing: 6) {
                Text(game.rules.mode.shortName)
                    .font(Theme.serif(compact ? 40 : 46))
                Text(game.isFinished ? "打完了" : "第 \(hand + 1) 局")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
            }
            .frame(width: compact ? 140 : 168, height: compact ? 140 : 168)
            .background {
                RoundedRectangle(cornerRadius: compact ? 22 : 26, style: .continuous)
                    .fill(Theme.white)
                    .shadow(color: Theme.ink.opacity(0.04), radius: 1, y: 1)
                    .shadow(color: Theme.ink.opacity(0.05), radius: 12, y: 8)
            }

            SeatLabel(game: game, player: at(2), hand: hand, alignment: .center)
                .frame(maxHeight: .infinity, alignment: .top)
            SeatLabel(game: game, player: at(0), hand: hand, alignment: .center)
                .frame(maxHeight: .infinity, alignment: .bottom)
            SeatLabel(game: game, player: at(3), hand: hand, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            SeatLabel(game: game, player: at(1), hand: hand, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: compact ? 256 : 304)
    }
}

private struct SeatLabel: View {
    var game: Game
    var player: Int
    var hand: Int
    var alignment: HorizontalAlignment

    private var winTag: String? {
        guard !game.isFinished else { return nil }
        if game.rules.mode == .xuezhan, let order = game.liveRound.xuezhanWinOrder(of: player) {
            let names = ["", "一胡", "二胡", "三胡"]
            return (1...3).contains(order) ? names[order] : "已胡"
        }
        if game.rules.mode == .xueliu {
            let count = game.liveRound.winCount(of: player)
            if count > 0 { return "胡×\(count)" }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 5) {
                Text(game.players[player].name)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if game.dealer(ofHand: hand) == player && !game.isFinished {
                    DealerStamp(size: 18)
                }
                if let winTag {
                    Text(winTag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.vermilion)
                }
            }
            Text(Theme.signed(game.scores[player]))
                .font(Theme.score(26))
                .foregroundStyle(Theme.scoreColor(game.scores[player]))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: alignment == .center ? nil : 84,
               alignment: alignment == .leading ? .leading : alignment == .trailing ? .trailing : .center)
    }
}

/// 账本里的一条记录。
private struct RecordRow: View {
    var number: Int
    var record: HandRecord
    var game: Game

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(record.handIndex + 1)")
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(Theme.gray)
                    .frame(width: 18, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title(in: game)).font(.system(size: 16))
                    Text(record.detail(in: game))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                }
                Spacer(minLength: 8)
                if let value = record.headline {
                    Text(Theme.signed(value))
                        .font(.system(size: 17).monospacedDigit())
                        .foregroundStyle(Theme.scoreColor(value))
                } else {
                    Text("—").font(.system(size: 17)).foregroundStyle(Theme.gray)
                }
            }
            .padding(.vertical, 14)
            Hairline(color: Theme.lineSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 记下后底部的黑色提示条。
private struct UndoBar: View {
    var text: String
    var undo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(text).font(.system(size: 14))
            Button(action: undo) {
                Text("撤销")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(.white.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .frame(height: 40)
        .background(Theme.ink, in: Capsule())
    }
}

// MARK: - 刮风下雨（记杠）

private struct KongSheet: View {
    @Environment(\.dismiss) private var dismiss
    var game: Game
    var onRecord: (KongRecord) -> Void

    @State private var player: Int
    @State private var kind: KongRecord.Kind = .anGang
    @State private var discarder: Int?

    init(game: Game, onRecord: @escaping (KongRecord) -> Void) {
        self.game = game
        self.onRecord = onRecord
        _player = State(initialValue: game.liveRound.activePlayers.first ?? 0)
    }

    private var kong: KongRecord {
        KongRecord(player: player, kind: kind, discarder: discarder)
    }

    private var previewDeltas: [Int] {
        Payment.kongDeltas(kong: kong, activePlayers: game.liveRound.activePlayers, rules: game.rules)
    }

    private var canSave: Bool {
        game.liveRound.activePlayers.contains(player) && (kind != .zhiGang || discarder != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("谁杠了")
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            let active = game.rules.mode != .xuezhan || game.liveRound.activePlayers.contains(i)
                            ChoiceChip(
                                title: active ? game.players[i].name : "\(game.players[i].name)·已胡",
                                selected: player == i
                            ) {
                                player = i
                                if discarder == i { discarder = nil }
                            }
                            .disabled(!active)
                            .opacity(active ? 1 : 0.45)
                        }
                    }

                    SectionLabel("哪种杠")
                        .padding(.top, 24)
                        .padding(.bottom, 10)
                    SegmentedSwitch(
                        options: [
                            (KongRecord.Kind.anGang, "下雨·暗杠"),
                            (KongRecord.Kind.baGang, "刮风·巴杠"),
                            (KongRecord.Kind.zhiGang, "刮风·直杠"),
                        ],
                        selection: $kind
                    )
                    Text(kindHint)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 10)

                    if kind == .zhiGang {
                        SectionLabel("是谁打的？")
                            .padding(.top, 22)
                            .padding(.bottom, 10)
                        HStack(spacing: 8) {
                            ForEach((0..<4).filter { $0 != player && (game.rules.mode != .xuezhan || game.liveRound.activePlayers.contains($0)) }, id: \.self) { i in
                                ChoiceChip(title: game.players[i].name, selected: discarder == i) {
                                    discarder = i
                                }
                            }
                        }
                    }

                    if canSave {
                        SectionLabel("这把谁付多少")
                            .padding(.top, 24)
                            .padding(.bottom, 6)
                        DeltaGrid(game: game, deltas: previewDeltas)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .bottomBar {
                Button(canSave ? "记下" : "选一下是谁打的") {
                    onRecord(kong)
                    dismiss()
                }
                .buttonStyle(.primary)
                .disabled(!canSave)
            }
            .page()
            .navigationTitle("刮风下雨")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var kindHint: String {
        switch kind {
        case .anGang:
            return "自己摸齐 4 张暗杠，在场未胡每家付 \(2 * game.rules.basePoints) 分。"
        case .baGang:
            return "碰了以后又摸到第 4 张加杠，在场未胡每家付 \(game.rules.basePoints) 分。"
        case .zhiGang:
            return "别人打出的牌被你杠了，点杠的人自己付 \(2 * game.rules.basePoints) 分。"
        }
    }
}

// MARK: - 牌摸完了（流局 / 退税 / 查大叫）

private struct DrawSheet: View {
    @Environment(\.dismiss) private var dismiss
    var game: Game
    var onSettle: ([PlayerTingState]) -> Void
    var onPlainDraw: () -> Void

    @State private var states: [PlayerTingState]
    @State private var cameraPlayer: Int?

    init(game: Game, onSettle: @escaping ([PlayerTingState]) -> Void, onPlainDraw: @escaping () -> Void) {
        self.game = game
        self.onSettle = onSettle
        self.onPlainDraw = onPlainDraw
        let initial: [PlayerTingState] = (0..<4).map { p in
            if game.rules.mode == .xuezhan && !game.liveRound.activePlayers.contains(p) {
                return .alreadyWon
            }
            return .ting(maxFan: 0)
        }
        _states = State(initialValue: initial)
    }

    /// 只有在场有人「没下叫」时，才需要问「下叫了」的人大叫是几番！
    private var someoneNotTing: Bool {
        states.contains(.notTing)
    }

    private var hasAnyPenaltyOrRefund: Bool {
        settlementPreview.totalDeltas.contains { $0 != 0 }
    }

    private var settlementPreview: (totalDeltas: [Int], taxRefundDeltas: [Int], penaltyDeltas: [Int]) {
        Payment.drawSettlementDeltas(
            states: states,
            activePlayers: game.liveRound.activePlayers,
            kongs: game.liveRound.kongs,
            rules: game.rules
        )
    }

    var body: some View {
        let preview = settlementPreview
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.liveRound.kongs.isEmpty
                         ? "大家都下叫了就直接点下面进下一局；有人没下叫或花猪再点选。"
                         : "有人没下叫或花猪时点一下，他这局收的杠钱会自动退回（退税）。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 4)
                        .padding(.bottom, 12)

                    ForEach(0..<4, id: \.self) { p in
                        if states[p] != .alreadyWon {
                            playerRow(p)
                            Hairline(color: Theme.lineSoft)
                        }
                    }

                    if hasAnyPenaltyOrRefund {
                        SectionLabel(preview.taxRefundDeltas.contains(where: { $0 != 0 }) ? "退税与查叫合计" : "查叫赔付")
                            .padding(.top, 22)
                            .padding(.bottom, 6)
                        DeltaGrid(game: game, deltas: preview.totalDeltas)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .bottomBar {
                Button(hasAnyPenaltyOrRefund ? "记下退税与查叫（下一局）" : "直接下一局") {
                    if hasAnyPenaltyOrRefund {
                        onSettle(states)
                    } else {
                        onPlainDraw()
                    }
                    dismiss()
                }
                .buttonStyle(.primary)
            }
            .page()
            .navigationTitle("这局摸完了")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
            .fullScreenCover(isPresented: Binding(get: { cameraPlayer != nil }, set: { if !$0 { cameraPlayer = nil } })) {
                if let p = cameraPlayer {
                    RoundFlowView(game: game, mode: .tingCheck(player: p)) { _, _ in
                    } onFinishTingCheck: { tingState in
                        states[p] = tingState
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func playerRow(_ p: Int) -> some View {
        let kongGain = game.liveRound.refundableKongGain(for: p)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(game.players[p].name)
                    .font(.system(size: 16, weight: .medium))
                if kongGain > 0 && states[p].needsTaxRefund {
                    Text("自动退杠 -\(kongGain)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.vermilion)
                }
                Spacer()
                Button("拍牌帮忙看 ›") {
                    cameraPlayer = p
                }
                .buttonStyle(.text(size: 13))
            }

            HStack(spacing: 8) {
                ChoiceChip(title: "下叫了", selected: isTing(states[p])) {
                    if !isTing(states[p]) { states[p] = .ting(maxFan: 0) }
                }
                ChoiceChip(title: "没下叫", selected: states[p] == .notTing) {
                    states[p] = .notTing
                }
                ChoiceChip(title: "花猪", selected: states[p] == .huaZhu) {
                    states[p] = .huaZhu
                }
            }

            // 只有场上有人「没下叫」时，才需要问「下叫了」的人大叫是几番
            if someoneNotTing, case .ting(let maxFan, _) = states[p] {
                let cap = game.rules.fanCap > 0 ? game.rules.fanCap : 5
                HStack(spacing: 6) {
                    Text("大叫")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.gray)
                    ForEach(0...cap, id: \.self) { fan in
                        Button {
                            states[p] = .ting(maxFan: fan)
                        } label: {
                            Text("\(fan)番")
                                .font(.system(size: 13, weight: maxFan == fan ? .semibold : .regular))
                                .foregroundStyle(maxFan == fan ? .white : Theme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(maxFan == fan ? Theme.ink : Color.clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(maxFan == fan ? Theme.ink : Theme.line))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 14)
    }

    private func isTing(_ state: PlayerTingState) -> Bool {
        if case .ting = state { return true }
        return false
    }
}

// MARK: - 直接改分

/// 四个人的加减分，加起来得是 0。
private struct ManualScoreView: View {
    @Environment(\.dismiss) private var dismiss
    var game: Game
    var save: ([Int], String) -> Void

    @State private var inputs = ["", "", "", ""]
    @State private var note = ""

    private var deltas: [Int] {
        inputs.map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }

    private var sum: Int { deltas.reduce(0, +) }
    private var canSave: Bool { sum == 0 && deltas.contains { $0 != 0 } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("赢的填正数，输的填负数，四个人加起来要是 0。")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.gray)

                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { i in
                            if i > 0 { Hairline(color: Theme.lineSoft) }
                            HStack {
                                Text(game.players[i].name).font(.system(size: 17, weight: .medium))
                                Spacer()
                                TextField("0", text: $inputs[i])
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 20).monospacedDigit())
                                    .frame(width: 120)
                            }
                            .frame(minHeight: 54)
                        }
                    }
                    .block()

                    TextField("备注（可不填）", text: $note)
                        .font(.system(size: 16))
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Hairline() }

                    if sum != 0 {
                        Text("现在加起来是 \(Theme.signed(sum))，还差 \(Theme.signed(-sum)) 才平。")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.vermilion)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .bottomBar {
                Button("记下") {
                    save(deltas, note)
                    dismiss()
                }
                .buttonStyle(.primary)
                .disabled(!canSave)
            }
            .page()
            .navigationTitle("直接改分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
        }
    }
}
