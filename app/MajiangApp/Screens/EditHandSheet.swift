import SwiftUI
import MajiangKit

/// 改账本里的某一条记录：胡牌 / 刮风下雨 / 荒庄查叫 / 流局 / 诈胡之间查看或修改，或者直接删掉。
/// 改完以后这一笔之后的局内状态、退税、呼叫转移和分数由 `Game.replace` 重算。
struct EditHandSheet: View {
    @Environment(\.dismiss) private var dismiss
    var game: Game
    var record: HandRecord
    var number: Int
    var onSave: (HandOutcome) -> Void
    var onDelete: () -> Void

    private enum Kind: Hashable { case win, kong, drawSettlement, drawn, falseWin, manual }

    @State private var kind: Kind
    @State private var winner: Int
    @State private var selfDrawn: Bool
    @State private var discarder: Int?
    @State private var fanEdit: Int?
    @State private var kongPlayer: Int
    @State private var kongKind: KongRecord.Kind
    @State private var kongDiscarder: Int?
    @State private var tingStates: [PlayerTingState]
    @State private var offender: Int
    @State private var confirmDelete = false

    init(game: Game, record: HandRecord, number: Int,
         onSave: @escaping (HandOutcome) -> Void, onDelete: @escaping () -> Void) {
        self.game = game
        self.record = record
        self.number = number
        self.onSave = onSave
        self.onDelete = onDelete

        let stateBefore = game.roundState(beforeRecord: record.id)
        let defaultStates: [PlayerTingState] = (0..<4).map { p in
            if game.rules.mode == .xuezhan && !stateBefore.activePlayers.contains(p) {
                return .alreadyWon
            }
            return .ting(maxFan: 0)
        }

        switch record.outcome {
        case .win(let win):
            _kind = State(initialValue: .win)
            _winner = State(initialValue: win.winner)
            _selfDrawn = State(initialValue: win.isSelfDrawn)
            _discarder = State(initialValue: win.discarder)
            _kongPlayer = State(initialValue: win.winner)
            _kongKind = State(initialValue: .anGang)
            _kongDiscarder = State(initialValue: nil)
            _tingStates = State(initialValue: defaultStates)
            _offender = State(initialValue: win.winner)
        case .kong(let kong):
            _kind = State(initialValue: .kong)
            _winner = State(initialValue: kong.player)
            _selfDrawn = State(initialValue: true)
            _discarder = State(initialValue: nil)
            _kongPlayer = State(initialValue: kong.player)
            _kongKind = State(initialValue: kong.kind)
            _kongDiscarder = State(initialValue: kong.discarder)
            _tingStates = State(initialValue: defaultStates)
            _offender = State(initialValue: kong.player)
        case .drawSettlement(let settlement):
            _kind = State(initialValue: .drawSettlement)
            _winner = State(initialValue: 0)
            _selfDrawn = State(initialValue: true)
            _discarder = State(initialValue: nil)
            _kongPlayer = State(initialValue: 0)
            _kongKind = State(initialValue: .anGang)
            _kongDiscarder = State(initialValue: nil)
            _tingStates = State(initialValue: settlement.states)
            _offender = State(initialValue: 0)
        case .falseWin(let offender):
            _kind = State(initialValue: .falseWin)
            _winner = State(initialValue: offender)
            _selfDrawn = State(initialValue: true)
            _discarder = State(initialValue: nil)
            _kongPlayer = State(initialValue: offender)
            _kongKind = State(initialValue: .anGang)
            _kongDiscarder = State(initialValue: nil)
            _tingStates = State(initialValue: defaultStates)
            _offender = State(initialValue: offender)
        case .drawn:
            _kind = State(initialValue: .drawn)
            _winner = State(initialValue: 0)
            _selfDrawn = State(initialValue: true)
            _discarder = State(initialValue: nil)
            _kongPlayer = State(initialValue: 0)
            _kongKind = State(initialValue: .anGang)
            _kongDiscarder = State(initialValue: nil)
            _tingStates = State(initialValue: defaultStates)
            _offender = State(initialValue: 0)
        case .manual:
            _kind = State(initialValue: .manual)
            _winner = State(initialValue: 0)
            _selfDrawn = State(initialValue: true)
            _discarder = State(initialValue: nil)
            _kongPlayer = State(initialValue: 0)
            _kongKind = State(initialValue: .anGang)
            _kongDiscarder = State(initialValue: nil)
            _tingStates = State(initialValue: defaultStates)
            _offender = State(initialValue: 0)
        }
    }

    private var originalWin: WinRecord? {
        if case .win(let win) = record.outcome { return win }
        return nil
    }

    private var kinds: [(Kind, String)] {
        switch record.outcome {
        case .kong:
            return [(.kong, "刮风下雨"), (.win, "胡牌"), (.falseWin, "诈胡")]
        case .drawSettlement, .drawn:
            return [(.drawSettlement, "查叫与退税"), (.drawn, "直接流局")]
        case .manual:
            return [(.manual, "直接改分")]
        default:
            return [(.win, "胡牌"), (.kong, "刮风下雨"), (.drawSettlement, "流局查叫"), (.falseWin, "诈胡")]
        }
    }

    private var outcome: HandOutcome? {
        switch kind {
        case .win:
            if !selfDrawn && discarder == nil { return nil }
            var win = originalWin ?? WinRecord(
                winner: winner,
                discarder: nil,
                hand: nil,
                context: WinContext(),
                fans: [],
                fanOverride: game.rules.minimumFan
            )
            win.winner = winner
            win.discarder = selfDrawn ? nil : discarder
            if let fanEdit {
                win.fanOverride = fanEdit
                win.fans = []
            }
            return .win(win)
        case .kong:
            if kongKind == .zhiGang && kongDiscarder == nil { return nil }
            let tile = record.kong?.tile
            return .kong(KongRecord(player: kongPlayer, kind: kongKind, discarder: kongDiscarder, tile: tile))
        case .drawSettlement:
            return .drawSettlement(DrawSettlementRecord(states: tingStates))
        case .drawn:
            return .drawn
        case .falseWin:
            return .falseWin(offender: offender)
        case .manual:
            return record.outcome
        }
    }

    private var preview: Result<Game, GameError>? {
        guard let outcome else { return nil }
        do {
            return .success(try game.replacing(record.id, with: outcome))
        } catch let error as GameError {
            return .failure(error)
        } catch {
            return .failure(.recordNotFound)
        }
    }

    private var previewRecord: HandRecord? {
        guard case .success(let edited) = preview else { return nil }
        return edited.records.first { $0.id == record.id }
    }

    private var shownFan: Int {
        if let fanEdit { return fanEdit }
        if case .win(let win)? = previewRecord?.outcome { return win.totalFan }
        if case .failure(.belowMinimumFan(let fan))? = preview { return fan }
        return originalWin?.totalFan ?? game.rules.minimumFan
    }

    private var minimumFan: Int { game.rules.minimumFan }

    private var blockedReason: String? {
        if kind == .win && !selfDrawn && discarder == nil { return "选一下谁点的炮" }
        if kind == .kong && kongKind == .zhiGang && kongDiscarder == nil { return "选一下谁点的杠" }
        if case .failure(let error) = preview { return error.message }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if kinds.count > 1 {
                        SegmentedSwitch(options: kinds, selection: $kind)
                    }

                    switch kind {
                    case .win: winSection
                    case .kong: kongSection
                    case .drawSettlement: drawSettlementSection
                    case .drawn: note("本局荒庄流局，不计分并进入下一局。")
                    case .falseWin: falseWinSection
                    case .manual: note("直接改的分不能在这里改。要重填就删掉这一条，再从右上角「直接改分」记一条。")
                    }

                    if let previewRecord, previewRecord.deltas != [0, 0, 0, 0] {
                        SectionLabel("这一笔得失分")
                            .padding(.top, 28)
                            .padding(.bottom, 10)
                        deltaGrid(previewRecord.deltas)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .bottomBar {
                Button(blockedReason ?? "保存") {
                    if let outcome { onSave(outcome) }
                    dismiss()
                }
                .buttonStyle(.primary)
                .disabled(blockedReason != nil)
                Button("删掉这一条") { confirmDelete = true }
                    .buttonStyle(.text)
            }
            .page()
            .navigationTitle("改第 \(number) 笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
            .confirmationDialog("删掉第 \(number) 笔记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删掉", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("这一笔的分数全部退回，后面的局内状态与退税会自动重算。")
            }
            .onChange(of: winner) { _, new in
                if discarder == new { discarder = nil }
            }
            .onChange(of: kongPlayer) { _, new in
                if kongDiscarder == new { kongDiscarder = nil }
            }
        }
    }

    // MARK: 胡牌

    @ViewBuilder
    private var winSection: some View {
        SectionLabel("谁胡了")
            .padding(.top, 28)
            .padding(.bottom, 10)
        chips(selected: winner) { winner = $0 }

        SectionLabel("怎么胡的")
            .padding(.top, 28)
            .padding(.bottom, 10)
        SegmentedSwitch(options: [(true, "自摸"), (false, "点炮")], selection: $selfDrawn)
        if !selfDrawn {
            Text("是谁点的炮？")
                .font(.system(size: 14))
                .foregroundStyle(Theme.gray)
                .padding(.top, 10)
            HStack(spacing: 8) {
                ForEach((0..<4).filter { $0 != winner }, id: \.self) { i in
                    NameChip(name: game.players[i].name, selected: discarder == i) { discarder = i }
                }
            }
            .padding(.top, 10)
        }

        fanRow
            .block()
            .padding(.top, 22)
        Text(fanNote)
            .font(.system(size: 14))
            .foregroundStyle(Theme.gray)
            .padding(.top, 10)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var fanRow: some View {
        HStack {
            Text("番数（\(1 << min(shownFan, 10)) 倍）").font(.system(size: 16))
            Spacer()
            HStack(spacing: 14) {
                stepButton("minus", label: "少一番") { fanEdit = max(minimumFan, shownFan - 1) }
                    .disabled(shownFan <= minimumFan)
                Text("\(shownFan)")
                    .font(.system(size: 17).monospacedDigit())
                    .frame(minWidth: 28)
                stepButton("plus", label: "多一番") { fanEdit = shownFan + 1 }
            }
        }
        .frame(minHeight: 60)
    }

    private var fanNote: String {
        if fanEdit != nil || originalWin?.fanOverride != nil || originalWin == nil {
            return "番数是手填的，账本里不再列番种明细。"
        }
        if originalWin?.hand != nil {
            return "按拍下的牌自动算，换了谁胡、自摸还是点炮会重算。要直接改番数就点加减。"
        }
        return "要改番数就点加减。"
    }

    // MARK: 刮风下雨

    @ViewBuilder
    private var kongSection: some View {
        SectionLabel("谁开的杠")
            .padding(.top, 28)
            .padding(.bottom, 10)
        chips(selected: kongPlayer) { kongPlayer = $0 }

        SectionLabel("刮风还是下雨")
            .padding(.top, 28)
            .padding(.bottom, 10)
        SegmentedSwitch(
            options: [
                (KongRecord.Kind.anGang, "下雨·暗杠"),
                (KongRecord.Kind.baGang, "刮风·巴杠"),
                (KongRecord.Kind.zhiGang, "刮风·直杠"),
            ],
            selection: $kongKind
        )

        if kongKind == .zhiGang {
            Text("是谁点的杠？")
                .font(.system(size: 14))
                .foregroundStyle(Theme.gray)
                .padding(.top, 10)
            HStack(spacing: 8) {
                ForEach((0..<4).filter { $0 != kongPlayer }, id: \.self) { i in
                    NameChip(name: game.players[i].name, selected: kongDiscarder == i) { kongDiscarder = i }
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: 荒庄查叫与退税

    private var someoneNotTing: Bool {
        tingStates.contains(.notTing)
    }

    @ViewBuilder
    private var drawSettlementSection: some View {
        let stateBefore = game.roundState(beforeRecord: record.id)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<4, id: \.self) { p in
                if tingStates[p] != .alreadyWon {
                    let kongGain = stateBefore.refundableKongGain(for: p)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(game.players[p].name)
                                .font(.system(size: 16, weight: .medium))
                            if kongGain > 0 && tingStates[p].needsTaxRefund {
                                Text("自动退杠 -\(kongGain)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.vermilion)
                            }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            ChoiceChip(title: "下叫了", selected: isTing(tingStates[p])) {
                                if !isTing(tingStates[p]) { tingStates[p] = .ting(maxFan: 0) }
                            }
                            ChoiceChip(title: "没下叫", selected: tingStates[p] == .notTing) {
                                tingStates[p] = .notTing
                            }
                            ChoiceChip(title: "花猪", selected: tingStates[p] == .huaZhu) {
                                tingStates[p] = .huaZhu
                            }
                        }
                        if someoneNotTing, case .ting(let maxFan, _) = tingStates[p] {
                            let cap = game.rules.fanCap > 0 ? game.rules.fanCap : 5
                            HStack(spacing: 6) {
                                Text("大叫")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.gray)
                                ForEach(0...cap, id: \.self) { fan in
                                    Button {
                                        tingStates[p] = .ting(maxFan: fan)
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
                    Hairline(color: Theme.lineSoft)
                }
            }
        }
        .padding(.top, 12)
    }

    private func isTing(_ state: PlayerTingState) -> Bool {
        if case .ting = state { return true }
        return false
    }

    // MARK: 诈胡

    @ViewBuilder
    private var falseWinSection: some View {
        SectionLabel("谁诈胡了")
            .padding(.top, 28)
            .padding(.bottom, 10)
        chips(selected: offender) { offender = $0 }
        note("赔在场其余每家 \(game.rules.falseWinPenalty) 分，本局继续。")
    }

    // MARK: 小部件

    private func chips(selected: Int, pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                NameChip(name: game.players[i].name, selected: selected == i) { pick(i) }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Theme.gray)
            .padding(.top, 16)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func deltaGrid(_ deltas: [Int]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.players[i].name)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .lineLimit(1)
                    Text(Theme.signed(deltas[i]))
                        .font(Theme.score(22))
                        .foregroundStyle(Theme.scoreColor(deltas[i]))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 18)
        .block()
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Theme.line))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
