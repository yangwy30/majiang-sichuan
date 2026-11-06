import SwiftUI
import UIKit
import MajiangKit

/// 发到微信群的账本图：打完了就是结算（名次 + 最省事的转账），没打完就是现在的分数 + 最近几局。
/// 宽 360 点、按 3 倍渲染，在微信里点开是 1080 宽的清楚图片。
struct ShareCard: View {
    var game: Game

    private var scores: [Int] { game.scores }
    private var ranking: [Int] { Settlement.ranking(scores: scores) }
    private var transfers: [Transfer] { Settlement.minimalTransfers(scores: scores) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            standings.padding(.top, 22)
            if game.isFinished {
                transferList.padding(.top, 26)
                if let line = game.biggestWinLine {
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 18)
                }
            } else {
                recent.padding(.top, 26)
            }
            Text("拍照算番 · 拍一下，番和钱都算好")
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
                .padding(.top, 26)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(width: 360, alignment: .leading)
        .background(Theme.paper)
        .foregroundStyle(Theme.ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("和")
                    .font(Theme.serif(14))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Theme.vermilion, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(game.startedAt.dayLabel)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(game.rulesSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(game.isFinished ? "打完了" : "打到\(game.handLabel)")
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.3)
                Text(game.isFinished ? "一共 \(game.currentHandIndex) 局"
                     : "打了 \(game.currentHandIndex) 局 · 还剩 \(game.remainingHands) 局")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
            }
        }
    }

    private var standings: some View {
        VStack(spacing: 0) {
            Hairline()
            ForEach(Array(ranking.enumerated()), id: \.element) { place, player in
                HStack(spacing: 14) {
                    Text("\(place + 1)")
                        .font(Theme.serif(14))
                        .foregroundStyle(Theme.gray)
                        .frame(width: 12)
                    Text(game.players[player].name)
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(game.moneyText(scores[player]))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Theme.gray)
                    Text(Theme.signed(scores[player]))
                        .font(Theme.score(26))
                        .foregroundStyle(Theme.scoreColor(scores[player]))
                        .frame(minWidth: 64, alignment: .trailing)
                }
                .frame(height: 54)
                Hairline()
            }
        }
    }

    private var transferList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("这样转账最省事").padding(.bottom, 6)
            if transfers.isEmpty {
                Text("不用转账，正好打平。")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.gray)
                    .padding(.vertical, 8)
            }
            ForEach(Array(transfers.enumerated()), id: \.offset) { _, t in
                HStack(spacing: 8) {
                    Text(game.players[t.from].name)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.faint)
                    Text(game.players[t.to].name)
                    Spacer()
                    Text(game.moneyText(t.points))
                        .font(.system(size: 16, weight: .semibold).monospacedDigit())
                }
                .font(.system(size: 15))
                .frame(height: 36)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("最近几局").padding(.bottom, 4)
            if game.records.isEmpty {
                Text("还没有记录。")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                    .padding(.vertical, 8)
            }
            ForEach(Array(game.records.enumerated().reversed().prefix(4)), id: \.element.id) { number, record in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(number + 1)")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Theme.gray)
                        .frame(width: 16, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title(in: game)).font(.system(size: 14))
                        Text(record.detail(in: game))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.gray)
                    }
                    Spacer(minLength: 6)
                    if let value = record.headline {
                        Text(Theme.signed(value))
                            .font(.system(size: 15).monospacedDigit())
                            .foregroundStyle(Theme.scoreColor(value))
                    }
                }
                .padding(.vertical, 7)
            }
        }
    }
}

extension Game {
    /// 「最大的一手：杨，清一色 8 翻（倍满）」。
    var biggestWinLine: String? {
        guard let biggest = biggestWin else { return nil }
        let paid = rules.paidFan(biggest.win)
        let limit = Payment.limitName(han: paid, fu: biggest.win.fu, kiriageMangan: rules.kiriageMangan)
        let suffix = limit.map { "\($0) \(paid) 翻" } ?? "\(paid) 翻 \(biggest.win.fu) 符"
        return "最大的一手：\(players[biggest.win.winner].name)，"
            + (biggest.win.fans.first.map { "\($0.fan.name) · " } ?? "") + suffix
    }

    /// 文字版，复制到微信里直接能看。
    var shareText: String {
        let scores = self.scores
        var lines = [isFinished
                     ? "立直日麻 \(startedAt.dayLabel) · 打完了，一共 \(currentHandIndex) 局"
                     : "立直日麻 \(startedAt.dayLabel) · 打到\(handLabel)（打了 \(currentHandIndex) 局）"]
        for player in Settlement.ranking(scores: scores) {
            lines.append("\(players[player].name) \(Theme.signed(scores[player])) 点（\(moneyText(scores[player]))）")
        }
        if isFinished {
            let transfers = Settlement.minimalTransfers(scores: scores)
            if !transfers.isEmpty {
                lines.append("这样转账最省事：")
                for t in transfers {
                    lines.append("\(players[t.from].name) → \(players[t.to].name) \(moneyText(t.points))")
                }
            }
            if let line = biggestWinLine { lines.append(line) }
        } else if let last = records.last {
            lines.append("上一局：\(last.title(in: self))")
        }
        return lines.joined(separator: "\n")
    }

    /// 账本图。
    @MainActor
    func shareImage() -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(game: self))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 系统分享面板（微信、存图、隔空投送……）。从最上层的页面弹出，sheet 里也能用。
enum ShareSheet {
    @MainActor
    static func present(_ items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY, width: 0, height: 0)
        top.present(controller, animated: true)
    }

    /// 发账本图；渲染不出来就退回文字。
    @MainActor
    static func share(_ game: Game) {
        if let image = game.shareImage() {
            present([image])
        } else {
            present([game.shareText])
        }
    }
}
