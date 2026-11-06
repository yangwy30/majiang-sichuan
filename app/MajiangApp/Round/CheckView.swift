import SwiftUI
import MajiangKit

/// 核对：支持 14 张胡牌拍照算番 与 13 张荒庄拍照查花猪/查大叫。
struct CheckView: View {
    @Environment(AppModel.self) private var model
    @Bindable var flow: RoundFlow
    var finish: (HandOutcome) -> Void
    var finishTing: ((PlayerTingState) -> Void)? = nil

    @State private var editingIndex: Int?
    @State private var addingTile = false
    @State private var addingMeld = false
    @State private var showInviteSheet = false
    @State private var tilesDropped = false

    private let tileColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        let resolution = flow.resolution
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !flow.isTingCheck {
                    whoSection
                } else {
                    tingHeaderSection
                }

                reviewBanner(resolution)
                inviteBanner

                tilesSection(resolution)
                    .padding(.top, 26)

                meldsSection
                    .padding(.top, 24)

                if flow.isTingCheck {
                    tingResultSection
                        .padding(.top, 26)
                } else {
                    assistanceSection(resolution)

                    specialSection
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .bottomBar {
            if flow.isTingCheck {
                Button(flow.blockedReason ?? "确认：\(flow.tingState.label)") {
                    finishTing?(flow.tingState)
                }
                .buttonStyle(.primary)
                .disabled(flow.blockedReason != nil)
            } else {
                Button(primaryTitle) {
                    flow.showResult = true
                }
                .buttonStyle(.primary)
                .disabled(flow.blockedReason != nil)
            }
        }
        .page()
        .navigationTitle(flow.isTingCheck ? "查花猪 / 查大叫" : "核对手牌")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            NavBack(flow.photo == nil ? "拍照" : "重拍") { flow.steps.removeAll() }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            tilesDropped = true
        }
        .sheet(isPresented: Binding(get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } })) {
            if let index = editingIndex, flow.concealed.indices.contains(index) {
                TileInspectorSheet(
                    recognized: flow.concealed[index],
                    recommended: resolution.recommended[index],
                    markedForRemoval: resolution.removals.contains(index),
                    isWinning: !flow.isTingCheck && flow.winningTileIndex == index,
                    onPick: { flow.choose($0, at: index) },
                    onConfirm: { flow.confirmTile(at: index) },
                    onSetWinning: { flow.winningTileIndex = index },
                    onRemove: { flow.removeTile(at: index) }
                )
            }
        }
        .sheet(isPresented: $addingTile) {
            TileEditSheet(title: "加一张牌", current: nil) { tile in
                flow.addTile(tile)
            }
        }
        .sheet(isPresented: $addingMeld) {
            MeldEditSheet { meld in
                flow.addMeld(meld)
            }
        }
        .sheet(isPresented: $flow.showResult) {
            if let win = flow.winRecord, let deltas = flow.previewDeltas {
                ResultSheet(game: flow.game, win: win, deltas: deltas) {
                    finish(.win(win))
                }
            }
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteView()
        }
    }

    private var primaryTitle: String {
        if let reason = flow.blockedReason { return reason }
        if let win = flow.winRecord {
            let paid = flow.game.rules.paidFan(win)
            let mult = flow.game.rules.paidMultiplier(win)
            return "算好了：\(paid) 番 · \(mult) 倍"
        }
        return "算番"
    }

    // MARK: 查大叫顶部说明 & 结果预览

    private var tingHeaderSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("检查 \(flow.game.players[flow.winner].name) 的 13 张未胡手牌")
                .font(.system(size: 20, weight: .semibold))
            Text("系统自动检查是否缺一门（判花猪），并穷举 27 种川麻牌张算出最高可能番数（大叫）。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.gray)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var tingResultSection: some View {
        let res = flow.tingCheckResult
        SectionLabel("查叫判定")
            .padding(.bottom, 10)
        if flow.tileUnitCount != 13 {
            VStack(alignment: .leading, spacing: 6) {
                Text("请先把牌核对到 13 张（当前 \(flow.tileUnitCount) 张）")
                    .font(.system(size: 16, weight: .semibold))
                Text("如果有暗杠或明杠（4 张），点下方「+ 碰 / 杠」加进副露，每组杠按 3 张计入 13 张。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
            }
            .padding(.vertical, 14)
            .block()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                switch res.status {
                case .huaZhu:
                    HStack(spacing: 8) {
                        Text("花猪")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.vermilion, in: Capsule())
                        Text("万、筒、条三门俱全")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.vermilion)
                    }
                    Text("按川麻规则：花猪需退还本局收到的所有刮风下雨杠钱，并向在场所有非花猪玩家赔封顶番（\(flow.game.rules.fanCap > 0 ? "\(flow.game.rules.fanCap) 番 \(1 << flow.game.rules.fanCap) 倍" : "4 番 16 倍")）。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                case .notTing:
                    HStack(spacing: 8) {
                        Text("未下叫")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.line, in: Capsule())
                        Text("已缺一门，但尚未听牌")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    Text("按川麻规则：未下叫需退还本局收到的所有刮风下雨杠钱（退税），并向已下叫玩家按其大叫番数赔付。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                case .ting:
                    let cappedFan = flow.game.rules.cappedFan(res.maxFan)
                    HStack(alignment: .firstTextBaseline) {
                        Text("已下叫 · 大叫 \(cappedFan) 番（\(1 << cappedFan) 倍）")
                            .font(.system(size: 18, weight: .semibold))
                        Spacer()
                        if cappedFan < res.maxFan {
                            Text("原 \(res.maxFan) 番封顶")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.gray)
                        }
                    }
                    Text("不用退税，且可向未下叫玩家收 \(cappedFan) 番（\(1 << cappedFan) 倍）。可胡牌张明细：")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                    VStack(spacing: 8) {
                        ForEach(res.waits, id: \.tile) { wait in
                            HStack(spacing: 10) {
                                TileFace(tile: wait.tile, width: 28)
                                Text("胡 \(wait.tile.displayName)")
                                    .font(.system(size: 15, weight: .medium))
                                Text(wait.result.fans.map(\.fan.name).joined(separator: "·"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.gray)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(wait.totalFan) 番 (\(wait.baseMultiplier)倍)")
                                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 14)
            .block()
        }
    }

    // MARK: 谁胡了 · 怎么胡的

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("谁胡了")
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    let active = flow.isPlayerActive(i)
                    NameChip(
                        name: active ? flow.game.players[i].name : "\(flow.game.players[i].name)·已胡",
                        selected: flow.winnerChosen && flow.winner == i
                    ) {
                        flow.pickWinner(i)
                    }
                    .disabled(!active)
                    .opacity(active ? 1 : 0.45)
                }
            }

            SectionLabel("怎么胡的")
                .padding(.top, 6)
            HStack(spacing: 8) {
                NameChip(name: "自摸", selected: flow.howChosen && flow.selfDrawn) {
                    flow.pickSelfDrawn()
                }
                ForEach((0..<4).filter { (!flow.winnerChosen || $0 != flow.winner) && flow.isPlayerActive($0) }, id: \.self) { i in
                    NameChip(name: "\(flow.game.players[i].name)点炮",
                             selected: flow.howChosen && !flow.selfDrawn && flow.discarder == i) {
                        flow.pickDiscarder(i)
                    }
                }
            }

            if flow.selfDrawn, flow.specials.contains(.kongReplacement), flow.game.rules.dianGangHuaRule == .asDianPao {
                SectionLabel("是谁点的杠？（点杠花算点炮）")
                    .padding(.top, 6)
                HStack(spacing: 8) {
                    ForEach((0..<4).filter { $0 != flow.winner && flow.isPlayerActive($0) }, id: \.self) { i in
                        NameChip(
                            name: "\(flow.game.players[i].name)点杠",
                            selected: flow.dianGangDiscarder == i
                        ) {
                            flow.dianGangDiscarder = i
                        }
                    }
                }
            }
        }
    }

    // MARK: 双读状态与复核提示

    @ViewBuilder
    private func reviewBanner(_ resolution: RecognitionResolution) -> some View {
        if flow.isReviewing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("已按端侧认牌摆好（自动过滤字牌/花牌），正在复核…")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
            }
            .padding(.top, 18)
        } else if resolution.hasRecommendations {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(recommendationSummary(resolution))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("按推荐改") { flow.applyRecommended(resolution) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.vermilion)
            }
            .padding(.vertical, 12)
            .block()
            .padding(.top, 18)
        } else if flow.concealed.contains(where: \.needsReview) {
            Text("标红点的牌两遍读得不一样，点开选一下。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.vermilion)
                .padding(.top, 18)
        }
    }

    private func recommendationSummary(_ resolution: RecognitionResolution) -> String {
        var parts: [String] = []
        for (i, tile) in resolution.recommended.sorted(by: { $0.key < $1.key }) where flow.concealed.indices.contains(i) {
            parts.append("第 \(i + 1) 张选 \(tile.displayName)")
        }
        for i in resolution.removals where flow.concealed.indices.contains(i) {
            parts.append("删掉多的 \(flow.concealed[i].tile.displayName)")
        }
        return parts.joined(separator: "、") + " 正好成胡。"
    }

    @ViewBuilder
    private var inviteBanner: some View {
        if let message = flow.inviteFailure {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(message)，这次先用端侧认牌。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                Spacer(minLength: 8)
                Button("重填") { showInviteSheet = true }
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.top, 14)
        }
    }

    // MARK: 立牌

    private func tilesSection(_ resolution: RecognitionResolution) -> some View {
        let target = flow.targetTileCount
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("手牌 · \(flow.tileUnitCount) / \(target)")
                Spacer()
                Text(flow.isTingCheck ? "点牌可换或删" : "点牌可换、删，或改哪张是胡的")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.gray)
            }

            if flow.concealed.isEmpty {
                Button { addingTile = true } label: {
                    Text(flow.isTingCheck ? "还没有牌，点这里一张张选满 13 张" : "还没有牌，点这里一张张选")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.gray)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: tileColumns, spacing: 10) {
                    ForEach(Array(flow.concealed.enumerated()), id: \.offset) { index, recognized in
                        tileCell(index: index, recognized: recognized, resolution: resolution)
                            .offset(y: tilesDropped ? 0 : -14)
                            .opacity(tilesDropped ? 1 : 0)
                            .animation(.spring(response: 0.36, dampingFraction: 0.78).delay(Double(index) * 0.018),
                                       value: tilesDropped)
                    }
                    if flow.tileUnitCount < target + 2 {
                        Button { addingTile = true } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Theme.line, lineWidth: 1)
                                    .frame(width: 40, height: 55)
                                    .overlay(Image(systemName: "plus").font(.system(size: 15)).foregroundStyle(Theme.gray))
                                Text(" ").font(.system(size: 11))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("加一张牌")
                    }
                }
            }

            ForEach(flow.recognitionNotes.filter { !$0.contains("邀请码") }, id: \.self) { note in
                Text(note).font(.system(size: 13)).foregroundStyle(Theme.gray)
            }
        }
    }

    private func tileCell(index: Int, recognized: RecognizedTile, resolution: RecognitionResolution) -> some View {
        let isWinning = !flow.isTingCheck && flow.winningTileIndex == index
        let removing = resolution.removals.contains(index)
        return Button {
            editingIndex = index
        } label: {
            VStack(spacing: 4) {
                TileFace(tile: recognized.tile, width: 40, state: removing ? .dim : .normal)
                    .overlay(alignment: .topTrailing) {
                        if recognized.needsReview {
                            Circle()
                                .fill(Theme.vermilion)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -3)
                        }
                    }
                if removing {
                    Text("多了")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.vermilion)
                } else if let rec = resolution.recommended[index] {
                    Text(rec.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.vermilion)
                } else {
                    Text(isWinning ? "胡" : " ")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.vermilion)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(recognized.tile.displayName)\(isWinning ? "，胡的这张" : "")\(recognized.needsReview ? "，待确认" : "")")
    }

    // MARK: 副露（碰/杠）

    private var meldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("亮在桌上的碰 / 杠（计入根）")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(flow.melds.enumerated()), id: \.offset) { index, meld in
                        Button {
                            flow.removeMeld(at: index)
                        } label: {
                            HStack(spacing: 6) {
                                Text(meld.displayText).font(.system(size: 14, weight: .medium))
                                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.gray)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .overlay(Capsule().strokeBorder(Theme.line))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删掉\(meld.displayText)")
                    }
                    if flow.melds.count < 4 {
                        Button {
                            addingMeld = true
                        } label: {
                            Text("+ 碰 / 杠")
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .overlay(Capsule().strokeBorder(Theme.line))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: 凑不齐时的提示与一键改牌

    @ViewBuilder
    private func assistanceSection(_ resolution: RecognitionResolution) -> some View {
        if case .failure = flow.scoring, !resolution.hasRecommendations {
            let detail = WinAssistant.explain(flow.hand, context: flow.context, minimumFan: flow.game.rules.minimumFan)
                ?? "请核对牌面。"
            let fixes = WinAssistant.fixSuggestions(for: flow.hand, context: flow.context, minimumFan: flow.game.rules.minimumFan)
            VStack(alignment: .leading, spacing: 10) {
                Text(flow.blockedReason ?? "还不能胡牌").font(.system(size: 16, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                    .fixedSize(horizontal: false, vertical: true)
                if !fixes.isEmpty {
                    Text("是不是拍错了其中一张？")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(fixes.prefix(5)) { fix in
                                Button {
                                    flow.apply(fix)
                                } label: {
                                    Text(fixLabel(fix))
                                        .font(.system(size: 13, weight: .medium))
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 34)
                                        .overlay(Capsule().strokeBorder(Theme.line))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .block()
            .padding(.top, 24)
        }
    }

    private func fixLabel(_ fix: HandFix) -> String {
        if let from = fix.from {
            return "\(from.displayName) → \(fix.to.displayName)（\(fix.topFanName) \(fix.totalFan)番）"
        }
        return "+ \(fix.to.displayName)（\(fix.topFanName) \(fix.totalFan)番）"
    }

    // MARK: 特殊情况（杠上开花、杠上炮呼叫转移、抢杠胡、海底、天地胡）

    private var specialSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("特殊胡牌（没有就不用管）")
                .padding(.bottom, 8)
            if flow.callTransferPreview > 0 {
                Text("已勾选杠上炮：将自动触发「呼叫转移」，把点炮者刚收的 +\(flow.callTransferPreview) 分杠钱转给胡牌者！")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.vermilion)
                    .padding(.bottom, 8)
            }
            Hairline()
            ForEach(SpecialWin.allCases, id: \.self) { special in
                let reason = special.unavailableReason(hand: flow.hand, selfDrawn: flow.selfDrawn)
                let selected = flow.specials.contains(special)
                Button {
                    flow.toggle(special)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(special.name) · +\(special.fanPoints) 番")
                                .font(.system(size: 16, weight: .medium))
                            Text(reason ?? special.plain)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selected ? Theme.ink : Theme.line)
                    }
                    .padding(.vertical, 12)
                    .opacity(reason == nil ? 1 : 0.4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(reason != nil)
                Hairline()
            }
        }
    }
}

/// 点开一张立牌：有两遍读得不一样的候选牌就放最上面一键换；也能设成胡的那张、删掉、或者从 27 种川麻牌里重选。
private struct TileInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    var recognized: RecognizedTile
    var recommended: Tile?
    var markedForRemoval: Bool
    var isWinning: Bool
    var onPick: (Tile) -> Void
    var onConfirm: () -> Void
    var onSetWinning: () -> Void
    var onRemove: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if recognized.candidates.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("两遍读得不一样，是哪张？")
                            HStack(spacing: 12) {
                                ForEach(recognized.candidates, id: \.self) { candidate in
                                    Button {
                                        onPick(candidate)
                                        dismiss()
                                    } label: {
                                        VStack(spacing: 6) {
                                            TileFace(tile: candidate, width: 48)
                                            Text(candidate == recommended ? "\(candidate.displayName) · 推荐" : candidate.displayName)
                                                .font(.system(size: 13, weight: candidate == recommended ? .semibold : .regular))
                                                .foregroundStyle(candidate == recommended ? Theme.vermilion : Theme.ink)
                                        }
                                        .padding(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(candidate == recognized.tile ? Theme.ink : Theme.line, lineWidth: candidate == recognized.tile ? 2 : 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else if recognized.uncertain {
                        HStack {
                            Text(markedForRemoval ? "这张多半是多读进来的" : "只有一遍读到这张 \(recognized.tile.displayName)")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.gray)
                            Spacer()
                            Button("有这张") {
                                onConfirm()
                                dismiss()
                            }
                            .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.vertical, 10)
                        .block()
                    }

                    HStack(spacing: 10) {
                        if !isWinning {
                            Button {
                                onSetWinning()
                                dismiss()
                            } label: {
                                Text("胡的是这张")
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
                            }
                            .buttonStyle(.plain)
                        }
                        Button(role: .destructive) {
                            onRemove()
                            dismiss()
                        } label: {
                            Text("删掉这张")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.vermilion)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("换成别的牌（川麻 108 张）")
                        TilePickerGrid(selected: recognized.tile) { tile in
                            onPick(tile)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .page()
            .navigationTitle(recognized.tile.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
