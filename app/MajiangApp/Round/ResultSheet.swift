import SwiftUI
import MajiangKit

/// 算番结果：几番几倍、哪几个番种与根、四个人各自付多少，点「记入账本」写进牌局。
struct ResultSheet: View {
    @Environment(\.dismiss) private var dismiss
    var game: Game
    var win: WinRecord
    var deltas: [Int]
    var onRecord: () -> Void

    private var paidFan: Int { game.rules.paidFan(win) }
    private var paidMult: Int { game.rules.paidMultiplier(win) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if paidFan < win.totalFan {
                        Text("桌规封顶 \(game.rules.fanCap) 番：原 \(win.totalFan) 番按 \(game.rules.fanCap) 番算")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.gray)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.lineSoft, in: Capsule())
                            .padding(.top, 8)
                    }
                    if win.callTransferAmount > 0 {
                        Text("杠上炮 · 呼叫转移：自动转走点炮者上一笔杠钱 +\(win.callTransferAmount) 分")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.vermilion)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.vermilion.opacity(0.1), in: Capsule())
                            .padding(.top, 8)
                    }
                    if let hand = win.hand {
                        HandTiles(hand: hand)
                            .padding(.top, 20)
                    }

                    SectionLabel("番种与根")
                        .padding(.top, 24)
                        .padding(.bottom, 6)
                    FanList(win: win)

                    SectionLabel("这把谁付多少")
                        .padding(.top, 24)
                        .padding(.bottom, 6)
                    DeltaGrid(game: game, deltas: deltas)
                    Text(game.paymentExplanation(win, deltas: deltas))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .bottomBar {
                Button("记入账本") { onRecord() }
                    .buttonStyle(.primary)
            }
            .page()
            .navigationTitle("算番结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose("返回") { dismiss() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(win.isSelfDrawn ? "\(game.players[win.winner].name)自摸" : "\(game.players[win.winner].name)胡")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.4)
                if let discarder = win.discarder {
                    Text("\(game.players[discarder].name)点炮")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                } else if game.rules.mode == .xuezhan {
                    let count = max(0, game.liveRound.activePlayers.filter { $0 != win.winner }.count)
                    Text("向在场未胡的 \(count) 家收钱")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                }
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(paidFan)")
                    .font(.system(size: 46, weight: .ultraLight).monospacedDigit())
                    .tracking(-1)
                Text("番").font(Theme.serif(18))
                Text("· \(paidMult) 倍")
                    .font(.system(size: 16, weight: .light).monospacedDigit())
                    .foregroundStyle(Theme.gray)
            }
        }
    }
}
