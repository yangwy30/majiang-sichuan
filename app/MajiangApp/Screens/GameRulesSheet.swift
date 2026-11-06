import SwiftUI
import MajiangKit

/// 打到一半改这场的规则。一场只用一套规则：改了以后前面的局一起重算，确认前先看每个人会变成多少。
struct GameRulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let game: Game
    var onSave: (GameRules) -> Void
    @State private var draft: GameRules

    /// `draft` 是打开时预先改好的规则（截图用），平时就是这场现在的规则。
    init(game: Game, draft: GameRules? = nil, onSave: @escaping (GameRules) -> Void) {
        self.game = game
        self.onSave = onSave
        _draft = State(initialValue: draft ?? game.rules)
    }

    private var changed: Bool { draft != game.rules }

    /// 按新规则重算以后的牌局；改不了（比如圈数少于已经打的局数）时是 nil。
    private var preview: Game? { try? game.changingRules(draft) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !game.records.isEmpty {
                        Text("一场只用一套规则，改了以后前面的局一起重算。")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.gray)
                            .padding(.bottom, 10)
                    }
                    HouseRulesForm(rules: $draft, playedHands: game.currentHandIndex)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .page()
            .navigationTitle("这场的规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
            .bottomBar {
                // 重算的结果贴在按钮上面，改哪一项都看得到，不用往下翻
                if changed, !game.records.isEmpty, let updated = preview {
                    previewBar(updated)
                        .padding(.bottom, 10)
                }
                Button(buttonTitle) {
                    if changed { onSave(draft) }
                    dismiss()
                }
                .buttonStyle(.primary)
                .disabled(changed && preview == nil)
            }
        }
        .presentationDetents([.large])
    }

    private var buttonTitle: String {
        guard changed else { return "好" }
        return game.records.isEmpty ? "改好了" : "改，前面 \(game.records.count) 局一起重算"
    }

    /// 每个人的分数从多少变成多少（四个人排一行）；起和调高后不够番的局单独说一句。
    private func previewBar(_ updated: Game) -> some View {
        let old = game.scores
        let new = updated.scores
        let moved = (0..<4).contains { old[$0] != new[$0] }
        let below = updated.winsBelowMinimum.compactMap { record in
            updated.records.firstIndex { $0.id == record.id }.map { "第 \($0 + 1) 局" }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Hairline()
            SectionLabel(moved ? "重算以后" : "前面的分数都不受影响")
                .padding(.top, 4)
            if moved {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(game.players[i].name)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.gray)
                                .lineLimit(1)
                            Text(Theme.signed(new[i]))
                                .font(Theme.score(22))
                                .foregroundStyle(Theme.scoreColor(new[i]))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            if old[i] != new[i] {
                                Text("原来 \(Theme.signed(old[i]))")
                                    .font(.system(size: 13).monospacedDigit())
                                    .foregroundStyle(Theme.gray)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !below.isEmpty {
                Text("\(below.joined(separator: "、"))的番数不够新的起和，先照样算着；要删可以在账本里点那一局。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
