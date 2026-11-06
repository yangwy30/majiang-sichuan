import SwiftUI
import MajiangKit

/// 结果：从下往上弹出的一层。大番数、每个番种一句白话、这局谁付多少。
struct ResultSheet: View {
    var flow: RoundFlow
    var finish: (HandOutcome) -> Void

    var body: some View {
        Group {
            if let record = flow.winRecord, let deltas = flow.deltas {
                content(record, deltas)
            } else {
                ContentUnavailableView("这手牌还胡不了", systemImage: "exclamationmark.circle")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .presentationBackground(Theme.paper)
    }

    private func content(_ record: WinRecord, _ deltas: [Int]) -> some View {
        let game = flow.game
        let name = { (i: Int) in game.players[i].name }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 谁胡、怎么胡的是记错最常见的地方：墨色写清楚，点一下收起结果回核对页改
                Button { flow.showResult = false } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(record.discarder.map { "\(name(record.winner)) · \(name($0))点炮" } ?? "\(name(record.winner)) · 自摸")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Theme.ink)
                        Text("改 ›")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.gray)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("回到核对页改谁胡了、怎么胡的")
                .padding(.top, 20)

                let paid = game.rules.paidFan(record)
                let mult = game.rules.paidMultiplier(record)
                let limit = Payment.limitName(han: paid)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(paid)")
                        .font(.system(size: 88, weight: .ultraLight).monospacedDigit())
                        .tracking(-2)
                    Text("番").font(Theme.serif(22))
                    Text("· \(mult) 倍")
                        .font(.system(size: 20, weight: .light).monospacedDigit())
                        .foregroundStyle(Theme.gray)
                    if let limit {
                        Text("· \(limit)")
                            .font(Theme.serif(20, semibold: true))
                            .foregroundStyle(Theme.vermilion)
                    }
                }
                .frame(maxWidth: .infinity)

                if paid < record.totalFan {
                    Text("桌规封顶 \(game.rules.fanCap) 番：\(record.totalFan) 番按 \(game.rules.fanCap) 番算")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.lineSoft, in: Capsule())
                        .frame(maxWidth: .infinity)
                }

                if record.callTransferAmount > 0 {
                    Text("杠上炮 · 呼叫转移：连同上一笔杠钱 +\(record.callTransferAmount) 分一并转交")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.vermilion)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.vermilion.opacity(0.1), in: Capsule())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }

                FanList(win: record)
                    .padding(.top, 14)

                SectionLabel("这把谁付多少")
                    .padding(.top, 22)
                    .padding(.bottom, 6)
                DeltaGrid(game: game, deltas: deltas)
                Text(game.paymentExplanation(record, deltas: deltas))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 24)
        }
        .bottomBar {
            Button("记下") { finish(.win(record)) }
                .buttonStyle(.primary)
        }
    }
}
