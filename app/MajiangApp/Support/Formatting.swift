import Foundation
import MajiangKit

extension HandRecord {
    /// 和牌记录；其它类型的事件返回 nil。
    var win: WinRecord? {
        if case .win(let win) = outcome { return win }
        return nil
    }

    /// 刮风下雨（杠）记录。
    var kong: KongRecord? {
        if case .kong(let kong) = outcome { return kong }
        return nil
    }

    /// 荒庄查叫（含退税）记录。
    var drawSettlement: DrawSettlementRecord? {
        if case .drawSettlement(let settlement) = outcome { return settlement }
        return nil
    }

    func title(in game: Game) -> String {
        switch outcome {
        case .kong(let kong):
            let tileText = kong.tile.map { " \($0.displayName)" } ?? ""
            return "\(game.players[kong.player].name)\(kong.kind.shortName)\(tileText)"
        case .win(let win):
            let orderPrefix: String
            if game.rules.mode == .xuezhan, (1...3).contains(win.winOrder) {
                let labels = ["", "一胡·", "二胡·", "三胡·"]
                orderPrefix = labels[win.winOrder]
            } else {
                orderPrefix = ""
            }
            return win.isSelfDrawn
                ? "\(game.players[win.winner].name)\(orderPrefix)自摸"
                : "\(game.players[win.winner].name)\(orderPrefix)胡"
        case .drawSettlement(let settlement):
            let hasTaxRefund = settlement.taxRefundDeltas.contains { $0 != 0 }
            let hasHuaZhu = settlement.states.contains(.huaZhu)
            if hasHuaZhu && hasTaxRefund { return "荒庄 · 查花猪/大叫 + 退税" }
            if hasTaxRefund { return "荒庄 · 查大叫 + 自动退税" }
            if hasHuaZhu { return "荒庄 · 查花猪/查大叫" }
            return "荒庄 · 查大叫"
        case .drawn:
            return "荒庄流局"
        case .falseWin(let offender):
            return "\(game.players[offender].name)诈胡"
        case .manual(_, let note):
            return note.isEmpty ? "直接改分" : note
        }
    }

    func detail(in game: Game) -> String {
        switch outcome {
        case .kong(let kong):
            switch kong.kind {
            case .zhiGang:
                let from = kong.discarder.map { "\(game.players[$0].name)点杠" } ?? "点杠"
                return "刮风 · \(from)（独付 \(2 * game.rules.basePoints) 分）"
            case .baGang:
                return "刮风·巴杠 · 在场未胡每家付 \(game.rules.basePoints) 分"
            case .anGang:
                return "下雨·暗杠 · 在场未胡每家付 \(2 * game.rules.basePoints) 分"
            }
        case .win(let win):
            let paid = game.rules.paidFan(win)
            let mult = game.rules.paidMultiplier(win)
            let capNote = paid < win.totalFan ? "（\(win.totalFan) 番封顶）" : ""
            let fanPart = "\(paid) 番\(capNote) · \(mult) 倍"
            let topFan = win.fans.first { $0.fan != .gen && $0.fan != .ziMoJiaFan }?.fan.name
                ?? win.fans.first?.fan.name
            let genEntry = win.fans.first { $0.fan == .gen }
            let genPart = genEntry.map { "带\($0.count)根" }
            let transferPart = win.callTransferAmount > 0 ? "呼叫转移+\(win.callTransferAmount)" : nil
            let who: String?
            if win.isSelfDrawn,
               win.context.gangShangHua,
               game.rules.dianGangHuaRule == .asDianPao,
               let p = win.context.dianGangDiscarder {
                who = "\(game.players[p].name)点杠包付"
            } else {
                who = win.discarder.map { "\(game.players[$0].name)点炮" }
            }
            return [fanPart, topFan, genPart, transferPart, who].compactMap { $0 }.joined(separator: " · ")
        case .drawSettlement(let settlement):
            var parts: [String] = []
            for p in 0..<4 {
                switch settlement.states[p] {
                case .alreadyWon:
                    break
                case .huaZhu:
                    parts.append("\(game.players[p].name)花猪")
                case .notTing:
                    parts.append("\(game.players[p].name)未下叫")
                case .ting(let maxFan, _):
                    parts.append("\(game.players[p].name)大叫\(maxFan)番")
                }
            }
            let refundedPlayers = (0..<4).filter { settlement.taxRefundDeltas[$0] < 0 }
                .map { "\(game.players[$0].name)退税\(-settlement.taxRefundDeltas[$0])分" }
            return (parts + refundedPlayers).joined(separator: " · ")
        case .drawn:
            return "不计分 · 推进下一局"
        case .falseWin:
            return "赔在场每家 \(game.rules.falseWinPenalty) 分"
        case .manual:
            return (0..<4).filter { deltas[$0] != 0 }
                .map { "\(game.players[$0].name) \(Theme.signed(deltas[$0]))" }
                .joined(separator: "  ")
        }
    }

    /// 账本右边的大数字：杠展示开杠者进账，胡展示胡牌者进账，诈胡展示罚分。
    var headline: Int? {
        switch outcome {
        case .kong(let kong): return deltas[kong.player]
        case .win(let win): return deltas[win.winner]
        case .drawSettlement:
            let best = deltas.max() ?? 0
            return best > 0 ? best : nil
        case .drawn: return nil
        case .falseWin(let offender): return deltas[offender]
        case .manual: return nil
        }
    }
}

extension Game {
    /// 把牌局分数折成人民币文字，整数不带小数点。
    func moneyText(_ points: Int) -> String {
        let yuan = money(forPoints: points)
        let absYuan = abs(yuan)
        let number = absYuan.rounded() == absYuan
            ? String(format: "%.0f", absYuan)
            : String(format: "%.1f", absYuan)
        return yuan < 0 ? "−¥\(number)" : "¥\(number)"
    }

    /// 牌桌顶上那一行：如「第 1 局 · 血战到底」。
    var handLabel: String {
        let roundNumber = min(currentHandIndex + 1, rules.totalHands)
        return "第 \(roundNumber) 局"
    }

    /// 牌桌副标题和分享卡右上角那一行短规则。
    var rulesSummary: String { rules.shortSummary }

    /// 一句话说清这手川麻的钱是怎么算出来的。
    func paymentExplanation(_ win: WinRecord, deltas: [Int]) -> String {
        let winnerName = players[win.winner].name
        let paidFan = rules.paidFan(win)
        let capText = paidFan < win.totalFan ? "（原 \(win.totalFan) 番，按 \(rules.fanCap) 番封顶）" : ""
        let mult = rules.paidMultiplier(win)
        let baseNote = rules.basePoints > 1 ? " × 底分 \(rules.basePoints)" : ""

        if win.isSelfDrawn {
            if win.context.gangShangHua,
               rules.dianGangHuaRule == .asDianPao,
               let payer = win.context.dianGangDiscarder {
                let pay = -deltas[payer]
                return "\(paidFan) 番\(capText) = \(mult) 倍\(baseNote)。家规「点杠花算点炮」，由点杠者\(players[payer].name)独付 \(pay) 分，\(winnerName)收 +\(deltas[win.winner]) 分。"
            }
            let zimoText = rules.zimoRule == .addDi ? "（2^\(paidFan) + 自摸加底 1 = \(mult) 倍）" : "（自摸加 1 番后 = \(mult) 倍）"
            let payers = (0..<4).filter { $0 != win.winner && deltas[$0] < 0 }.map { players[$0].name }
            let eachPay = payers.isEmpty ? mult * rules.basePoints : (-deltas[(0..<4).first { deltas[$0] < 0 } ?? 0])
            let payerNames = payers.joined(separator: "、")
            return "\(paidFan) 番\(capText)\(zimoText)\(baseNote)。在场未胡玩家（\(payerNames)）每家付 \(eachPay) 分，\(winnerName)共收 +\(deltas[win.winner]) 分。"
        } else {
            let discarderName = win.discarder.map { players[$0].name } ?? "点炮者"
            let basePay = mult * rules.basePoints
            if win.callTransferAmount > 0 {
                return "\(paidFan) 番\(capText) = \(mult) 倍\(baseNote)（\(basePay) 分），外加杠上炮「呼叫转移」转走\(discarderName)刚收的杠钱 \(win.callTransferAmount) 分，由\(discarderName)一共付 \(-deltas[win.discarder ?? 0]) 分。"
            }
            return "\(paidFan) 番\(capText) = \(mult) 倍\(baseNote)。\(discarderName)点炮独付 \(basePay) 分，\(winnerName)收 +\(deltas[win.winner]) 分。"
        }
    }

    /// 手牌底下那句「胡 7筒 · 自摸」或「胡 6筒 · 阿强点炮」。
    func winSentence(_ win: WinRecord) -> String? {
        guard let hand = win.hand else { return nil }
        let how = win.discarder.map { "\(players[$0].name)点炮" } ?? "自摸"
        let genText = hand.genCount > 0 ? " · \(hand.genCount) 根" : ""
        return "胡 \(hand.winningTile.displayName) · \(how)\(genText)"
    }
}

extension GameRules {
    /// 跟成都主流预设（血战到底、4番封顶、自摸加底、点杠花算自摸、1分底）不一样的地方，按顺序列成短句。
    var houseRuleParts: [String] {
        var parts: [String] = [mode.name]
        parts.append(fanCap == 0 ? "不封顶" : "\(fanCap)番封顶(\(1 << fanCap)倍)")
        parts.append(zimoRule.name)
        if dianGangHuaRule == .asDianPao { parts.append("点杠花算点炮") }
        if allowMenQing { parts.append("门清") }
        if allowZhongZhang { parts.append("中张") }
        if basePoints != 1 { parts.append("\(basePoints)分底") }
        return parts
    }

    /// 开局页和改家规页底下的那一行完整汇总。
    var summary: String {
        let yuan = yuanPerPoint.cleanNumber
        var parts = houseRuleParts
        parts.append("1 分 \(yuan) 元")
        parts.append("打 \(totalHands) 局")
        return parts.joined(separator: " · ")
    }

    /// 牌桌顶上和账本图右上角的短汇总。
    var shortSummary: String {
        let cap = fanCap == 0 ? "不封顶" : "\(fanCap)番封顶"
        return "\(mode.shortName) · \(cap) · \(zimoRule.name) · 1分¥\(yuanPerPoint.cleanNumber)"
    }

    /// 历史列表里跟在名字后面的小字。
    var houseRuleBadge: String? {
        return "\(mode.shortName)·\(fanCap == 0 ? "不封顶" : "\(fanCap)番顶")"
    }
}

extension Double {
    var cleanNumber: String {
        rounded() == self ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}

extension Date {
    var dayLabel: String {
        formatted(.dateTime.month().day())
    }
}
