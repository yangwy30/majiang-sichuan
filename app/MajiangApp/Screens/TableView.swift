import SwiftUI
import MajiangKit

struct TableView: View {
    @Environment(AppModel.self) private var model
    let gameID: UUID

    @State private var showRoundFlow = false
    @State private var showKongSheet = false
    @State private var showDrawSettlementSheet = false
    @State private var showFalseWin = false
    @State private var showManual = false
    @State private var showRules = false
    @State private var editingRecord: HandRecord?
    @State private var recordError: String?

    var body: some View {
        Group {
            if let game = model.game(gameID) {
                content(game)
            } else {
                ContentUnavailableView("牌局不存在", systemImage: "rectangle.portrait.slash")
            }
        }
        .page()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            NavBack("牌局") { model.path.removeAll() }
            if let game = model.game(gameID) {
                NavTool {
                    Menu {
                        Button("刮风 / 下雨（记杠）") { showKongSheet = true }
                        Button("荒庄流局（查花猪 / 查大叫 / 自动退税）") { showDrawSettlementSheet = true }
                        Button("普通荒庄（不查叫直接下一局）") { recordDraw() }
                        Button("有人诈胡（赔罚分）") { showFalseWin = true }
                        Button("直接改分") { showManual = true }
                        Divider()
                        Button("这场家规") { showRules = true }
                        Button("发战报到群里") { ShareSheet.share(game) }
                        if !game.records.isEmpty {
                            Button("撤销上一笔") { undo() }
                        }
                        Divider()
                        Button("结束牌局并结算") {
                            if var g = model.game(gameID) {
                                g.end()
                                model.update(g)
                            }
                            model.path = [.settle(gameID)]
                        }
                    } label: {
                        Text("更多")
                    }
                    .buttonStyle(NavButtonStyle())
                }
            }
        }
        .task {
            #if DEBUG
            if let screen = model.demoScreen {
                if screen.opensRound && !showRoundFlow { showRoundFlow = true }
                if screen == .editHand, editingRecord == nil { editingRecord = model.game(gameID)?.records.first }
                if screen == .gameRules && !showRules { showRules = true }
            }
            #endif
        }
    }

    private func content(_ game: Game) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusHeader(game)
                    .padding(.bottom, 14)

                TableDiagram(game: game)

                inRoundActionStrip(game)
                    .padding(.top, 16)

                ledger(game)
                    .padding(.top, 26)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .bottomBar {
            if game.isFinished {
                Button("看结算单") { model.path.append(.settle(gameID)) }
                    .buttonStyle(.primary)
            } else {
                Button(winButtonTitle(game)) { showRoundFlow = true }
                    .buttonStyle(.primary)
            }
        }
        .fullScreenCover(isPresented: $showRoundFlow) {
            RoundFlowView(game: game, mode: .win, demo: model.demoScreen) { outcome, photo in
                apply(outcome, photo: photo)
            }
        }
        .sheet(isPresented: $showKongSheet) {
            KongSheet(game: game) { kong in
                recordKong(kong)
            }
        }
        .sheet(isPresented: $showDrawSettlementSheet) {
            DrawSettlementSheet(game: game) { states in
                recordDrawSettlement(states)
            } onPlainDraw: {
                recordDraw()
            }
        }
        .sheet(isPresented: $showFalseWin) {
            FalseWinSheet(game: game) { offender in
                recordFalseWin(offender)
            }
        }
        .sheet(isPresented: $showManual) {
            ManualScoreSheet(game: game) { deltas, note in
                recordManual(deltas: deltas, note: note)
            }
        }
        .sheet(isPresented: $showRules) {
            GameRulesSheet(game: game) { newRules in
                changeRules(newRules)
            }
        }
        .sheet(item: $editingRecord) { record in
            let number = (game.records.firstIndex { $0.id == record.id } ?? 0) + 1
            EditHandSheet(game: game, record: record, number: number) { outcome in
                replace(record.id, with: outcome)
            } onDelete: {
                delete(record.id)
            }
        }
        .alert("记不上", isPresented: Binding(get: { recordError != nil }, set: { if !$0 { recordError = nil } })) {
            Button("好") { recordError = nil }
        } message: {
            Text(recordError ?? "")
        }
    }

    private func winButtonTitle(_ game: Game) -> String {
        if game.rules.mode == .xuezhan {
            let nextOrder = game.liveRound.wonPlayers.count + 1
            let labels = ["", "记一胡（拍照算番）", "记二胡（只收未胡 2 家）", "记三胡（收未胡最后 1 家）"]
            if (1...3).contains(nextOrder) {
                return labels[nextOrder]
            }
        }
        return "胡牌算番（拍照 / 手选）"
    }

    // MARK: 顶栏与局内快捷操作条

    private func statusHeader(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(game.isFinished ? "打完了" : "\(game.handLabel) · \(game.rules.mode.name)")
                .font(.system(size: 32, weight: .semibold))
                .tracking(-0.5)
            Button { showRules = true } label: {
                Text((game.isFinished
                      ? "一共 \(game.currentHandIndex) 局"
                      : "\(game.players[game.dealer].name)坐庄 · 还剩 \(game.remainingHands) 局")
                     + " · \(game.rulesSummary)")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func inRoundActionStrip(_ game: Game) -> some View {
        if !game.isFinished {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        showKongSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wind")
                                .font(.system(size: 14, weight: .semibold))
                            Text("刮风 / 下雨（记杠）")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showDrawSettlementSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "eye")
                                .font(.system(size: 14, weight: .semibold))
                            Text(game.rules.mode == .xuezhan && !game.liveRound.wonPlayers.isEmpty
                                 ? "荒庄查叫 / 退税"
                                 : "流局查大叫 / 退税")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if !game.liveRound.events.isEmpty {
                    let kongCount = game.liveRound.kongs.count
                    let winCount = game.liveRound.wonPlayers.count
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.vermilion)
                            .frame(width: 6, height: 6)
                        Text("本局进行中：已胡 \(winCount) 把 · 刮风下雨 \(kongCount) 杠（荒庄未下叫将自动退税）")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.gray)
                    }
                }
            }
        }
    }

    // MARK: 账本

    private func ledger(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("账本流水")
                .padding(.bottom, 8)
            Hairline()
            if game.records.isEmpty {
                Text("还没有记录。局中随时点「刮风/下雨」记杠，有人胡牌点底部「胡牌算番」，摸完荒庄点「流局查大叫 / 退税」。")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.gray)
                    .padding(.vertical, 20)
                Hairline()
            } else {
                ForEach(Array(game.records.enumerated().reversed()), id: \.element.id) { index, record in
                    Button {
                        if record.win != nil {
                            model.path.append(.hand(gameID, record.id))
                        } else {
                            editingRecord = record
                        }
                    } label: {
                        ledgerRow(game, number: index + 1, record: record)
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
            }
        }
    }

    private func ledgerRow(_ game: Game, number: Int, record: HandRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("第\(record.handIndex + 1)局")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.gray)
                .frame(width: 38, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title(in: game))
                    .font(.system(size: 16, weight: .medium))
                Text(record.detail(in: game))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.gray)
            }
            Spacer()
            if let value = record.headline {
                Text(Theme.signed(value))
                    .font(.system(size: 17).monospacedDigit())
                    .foregroundStyle(Theme.scoreColor(value))
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: 写入账本

    private func apply(_ outcome: HandOutcome, photo: UIImage? = nil) {
        guard var game = model.game(gameID) else { return }
        do {
            var newRecord: HandRecord?
            switch outcome {
            case .kong(let kong):
                newRecord = try game.recordKong(kong)
            case .win(let win):
                newRecord = try game.recordWin(win)
            case .drawSettlement(let settlement):
                newRecord = try game.recordDrawSettlement(states: settlement.states)
            case .drawn:
                newRecord = try game.recordDraw()
            case .falseWin(let offender):
                newRecord = try game.recordFalseWin(offender: offender)
            case .manual(let deltas, let note):
                newRecord = try game.recordManual(deltas: deltas, note: note)
            }
            model.update(game)
            if let photo, let id = newRecord?.id { HandPhotos.save(photo, for: id) }
            if game.isFinished { model.path.append(.settle(gameID)) }
        } catch let error as GameError {
            recordError = error.message
        } catch {
            recordError = error.localizedDescription
        }
    }

    private func recordKong(_ kong: KongRecord) { apply(.kong(kong)) }
    private func recordDrawSettlement(_ states: [PlayerTingState]) {
        apply(.drawSettlement(DrawSettlementRecord(states: states)))
    }
    private func recordDraw() { apply(.drawn) }
    private func recordFalseWin(_ offender: Int) { apply(.falseWin(offender: offender)) }
    private func recordManual(deltas: [Int], note: String) { apply(.manual(deltas: deltas, note: note)) }

    private func replace(_ id: UUID, with outcome: HandOutcome) {
        guard var game = model.game(gameID) else { return }
        do {
            try game.replace(id, with: outcome)
            model.update(game)
        } catch let error as GameError {
            recordError = error.message
        } catch {
            recordError = error.localizedDescription
        }
    }

    private func delete(_ id: UUID) {
        guard var game = model.game(gameID) else { return }
        game.remove(id)
        model.update(game)
        HandPhotos.delete(id)
    }

    private func changeRules(_ newRules: GameRules) {
        guard var game = model.game(gameID) else { return }
        do {
            try game.changeRules(newRules)
            model.update(game)
        } catch let error as GameError {
            recordError = error.message
        } catch {
            recordError = error.localizedDescription
        }
    }

    private func undo() {
        guard var game = model.game(gameID) else { return }
        if let removed = game.undoLast() { HandPhotos.delete(removed.id) }
        model.update(game)
    }
}

// MARK: - 牌桌方位图

private struct TableDiagram: View {
    var game: Game

    private var rotated: [Int] {
        let s = game.currentSeating
        let myPos = s.firstIndex(of: game.me) ?? 0
        return (0..<4).map { s[(myPos + $0) % 4] }
    }

    var body: some View {
        let p = rotated
        let scores = game.scores
        let dealer = game.dealer

        VStack(spacing: 14) {
            SeatLabel(game: game, player: p[2], score: scores[p[2]], isDealer: p[2] == dealer)

            HStack(spacing: 8) {
                SeatLabel(game: game, player: p[3], score: scores[p[3]], isDealer: p[3] == dealer)
                    .frame(maxWidth: .infinity)

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1)
                        .frame(width: 96, height: 96)
                    VStack(spacing: 2) {
                        Text(game.rules.mode.shortName)
                            .font(Theme.serif(24, semibold: true))
                        Text("第 \(min(game.currentHandIndex + 1, game.rules.totalHands)) 局")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.gray)
                    }
                }

                SeatLabel(game: game, player: p[1], score: scores[p[1]], isDealer: p[1] == dealer)
                    .frame(maxWidth: .infinity)
            }

            SeatLabel(game: game, player: p[0], score: scores[p[0]], isDealer: p[0] == dealer)
        }
        .padding(.vertical, 16)
        .block()
    }
}

private struct SeatLabel: View {
    var game: Game
    var player: Int
    var score: Int
    var isDealer: Bool

    private var statusBadge: String? {
        if game.rules.mode == .xuezhan, let order = game.liveRound.xuezhanWinOrder(of: player) {
            let names = ["", "一胡", "二胡", "三胡"]
            return (1...3).contains(order) ? names[order] : "已胡"
        }
        if game.rules.mode == .xueliu {
            let count = game.liveRound.winCount(of: player)
            if count > 0 { return "已胡×\(count)" }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(game.players[player].name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                if isDealer {
                    Text("庄")
                        .font(Theme.serif(11, semibold: true))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.vermilion, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                if let badge = statusBadge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.vermilion)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.vermilion.opacity(0.12), in: Capsule())
                }
            }
            Text(Theme.signed(score))
                .font(Theme.score(30))
                .foregroundStyle(Theme.scoreColor(score))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(game.moneyText(score))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.gray)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(game.players[player].name)\(isDealer ? "，庄" : "")\(statusBadge.map { "，\($0)" } ?? "")，\(score)分，\(game.moneyText(score))")
    }
}

// MARK: - 刮风下雨（记杠）弹窗

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

    private var blockedReason: String? {
        if !game.liveRound.activePlayers.contains(player) {
            return "\(game.players[player].name)在本局已胡离场"
        }
        if kind == .zhiGang && discarder == nil {
            return "选一下是谁点的杠"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("谁开的杠")
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { i in
                            let active = game.rules.mode != .xuezhan || game.liveRound.activePlayers.contains(i)
                            NameChip(
                                name: active ? game.players[i].name : "\(game.players[i].name)·已胡",
                                selected: player == i
                            ) {
                                player = i
                                if discarder == i { discarder = nil }
                            }
                            .disabled(!active)
                            .opacity(active ? 1 : 0.45)
                        }
                    }

                    SectionLabel("刮风还是下雨")
                        .padding(.top, 26)
                        .padding(.bottom, 10)
                    SegmentedSwitch(
                        options: [
                            (KongRecord.Kind.anGang, "下雨·暗杠"),
                            (KongRecord.Kind.baGang, "刮风·巴杠"),
                            (KongRecord.Kind.zhiGang, "刮风·直杠"),
                        ],
                        selection: $kind
                    )
                    Text(kindExplanation)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 10)

                    if kind == .zhiGang {
                        SectionLabel("是谁打牌点的杠？")
                            .padding(.top, 24)
                            .padding(.bottom, 10)
                        HStack(spacing: 8) {
                            ForEach((0..<4).filter { $0 != player && (game.rules.mode != .xuezhan || game.liveRound.activePlayers.contains($0)) }, id: \.self) { i in
                                NameChip(name: game.players[i].name, selected: discarder == i) {
                                    discarder = i
                                }
                            }
                        }
                    }

                    if blockedReason == nil {
                        SectionLabel("这笔杠钱（若荒庄未下叫将自动退税）")
                            .padding(.top, 26)
                            .padding(.bottom, 6)
                        DeltaGrid(game: game, deltas: previewDeltas)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .bottomBar {
                Button(blockedReason ?? "记入本局杠钱") {
                    onRecord(kong)
                    dismiss()
                }
                .buttonStyle(.primary)
                .disabled(blockedReason != nil)
            }
            .page()
            .navigationTitle("刮风 / 下雨（记杠）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var kindExplanation: String {
        switch kind {
        case .anGang:
            return "下雨（暗杠）：自己抓齐 4 张暗杠，向当前在场未胡每家收 \(2 * game.rules.basePoints) 分（2 倍底）。"
        case .baGang:
            return "刮风（巴杠/弯杠）：已碰的牌自己又摸到第 4 张加杠，向当前在场未胡每家收 \(game.rules.basePoints) 分（1 倍底）。"
        case .zhiGang:
            return "刮风（直杠/点杠）：手里一坎 3 张，别人打出第 4 张开杠，由点杠者独付 \(2 * game.rules.basePoints) 分（2 倍底）。"
        }
    }
}

// MARK: - 荒庄流局（查花猪 / 查大叫 / 自动退税）弹窗

private struct DrawSettlementSheet: View {
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
                    Text("牌墙摸完荒庄时，系统自动对「未下叫」与「花猪」玩家执行刮风下雨退税，并计算查花猪与查大叫赔付。可点「拍照查叫」直接拍 13 张手牌识别。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 4)
                        .padding(.bottom, 16)

                    ForEach(0..<4, id: \.self) { p in
                        playerRow(p)
                        Hairline()
                    }

                    if preview.taxRefundDeltas.contains(where: { $0 != 0 }) {
                        SectionLabel("自动退税明细（未下叫/花猪退回本局杠钱）")
                            .padding(.top, 22)
                            .padding(.bottom, 6)
                        DeltaGrid(game: game, deltas: preview.taxRefundDeltas)
                    }

                    SectionLabel("本局荒庄结算总计（含退税 + 查花猪 + 查大叫）")
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                    DeltaGrid(game: game, deltas: preview.totalDeltas)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .bottomBar {
                Button("确认荒庄结算并进入下一局") {
                    onSettle(states)
                    dismiss()
                }
                .buttonStyle(.primary)
                Button("不查叫，直接流局下一局") {
                    onPlainDraw()
                    dismiss()
                }
                .buttonStyle(.text)
            }
            .page()
            .navigationTitle("荒庄 · 查大叫与退税")
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
    }

    @ViewBuilder
    private func playerRow(_ p: Int) -> some View {
        let kongGain = game.liveRound.refundableKongGain(for: p)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(game.players[p].name)
                    .font(.system(size: 17, weight: .semibold))
                if kongGain > 0 {
                    Text("本局收杠 +\(kongGain) 分")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(states[p].needsTaxRefund ? Theme.vermilion : Theme.gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background((states[p].needsTaxRefund ? Theme.vermilion : Theme.line).opacity(0.15), in: Capsule())
                }
                Spacer()
                if states[p] != .alreadyWon {
                    Button {
                        cameraPlayer = p
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                            Text("拍照查叫(13张)")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Theme.vermilion)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Capsule().strokeBorder(Theme.vermilion.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                }
            }

            if states[p] == .alreadyWon {
                Text("本局已胡离场 · 不参与查叫与退税")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
            } else {
                HStack(spacing: 8) {
                    stateChip(title: "已下叫", isSelected: isTing(states[p])) {
                        if !isTing(states[p]) { states[p] = .ting(maxFan: 0) }
                    }
                    stateChip(title: "未下叫(退税)", isSelected: states[p] == .notTing) {
                        states[p] = .notTing
                    }
                    stateChip(title: "花猪(赔封顶)", isSelected: states[p] == .huaZhu) {
                        states[p] = .huaZhu
                    }
                }

                if case .ting(let maxFan, _) = states[p] {
                    HStack {
                        Text("大叫番数：\(maxFan) 番（\(1 << min(game.rules.cappedFan(maxFan), 10)) 倍）")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.gray)
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(0...5, id: \.self) { fan in
                                Button {
                                    states[p] = .ting(maxFan: fan)
                                } label: {
                                    Text("\(fan)番")
                                        .font(.system(size: 13, weight: maxFan == fan ? .semibold : .regular))
                                        .foregroundStyle(maxFan == fan ? .white : Theme.ink)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(maxFan == fan ? Theme.ink : Color.clear, in: Capsule())
                                        .overlay(Capsule().strokeBorder(maxFan == fan ? Theme.ink : Theme.line))
                                }
                                .buttonStyle(.plain)
                            }
                        }
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

    private func stateChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? .white : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(isSelected ? Theme.ink : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? Theme.ink : Theme.line))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 诈胡 & 直接改分

private struct FalseWinSheet: View {
    @Environment(\.dismiss) private var dismiss
    var game: Game
    var onPick: (Int) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("诈胡（错和）的人赔给在场其余每家 \(game.rules.falseWinPenalty) 分，本局继续。")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.gray)
                    .padding(.bottom, 16)
                Hairline()
                ForEach(0..<4, id: \.self) { i in
                    Button {
                        onPick(i)
                        dismiss()
                    } label: {
                        HStack {
                            Text(game.players[i].name).font(.system(size: 17, weight: .medium))
                            Spacer()
                            Text("-\(game.rules.falseWinPenalty * max(1, game.liveRound.activePlayers.filter { $0 != i }.count))")
                                .font(.system(size: 17).monospacedDigit())
                                .foregroundStyle(Theme.gray)
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Hairline()
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .page()
            .navigationTitle("谁诈胡了？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ManualScoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    var game: Game
    var onSave: ([Int], String) -> Void

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
                            if i > 0 { Hairline() }
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
                Button("记上") {
                    onSave(deltas, note)
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
