import Foundation

public struct Transfer: Hashable, Codable, Sendable {
    public let from: Int
    public let to: Int
    public let points: Int
}

public enum Settlement {
    /// 最少转账：先把正好互相抵消的两人配对，剩下的大额对大额。四个人时这样得到的笔数最少。
    public static func minimalTransfers(scores: [Int]) -> [Transfer] {
        var balance = scores
        var transfers: [Transfer] = []

        // 一收一付金额正好相等的，直接配对
        for debtor in balance.indices where balance[debtor] < 0 {
            if let creditor = balance.indices.first(where: { balance[$0] == -balance[debtor] }) {
                transfers.append(Transfer(from: debtor, to: creditor, points: balance[creditor]))
                balance[creditor] = 0
                balance[debtor] = 0
            }
        }

        while let debtor = balance.indices.filter({ balance[$0] < 0 }).min(by: { balance[$0] < balance[$1] }),
              let creditor = balance.indices.filter({ balance[$0] > 0 }).max(by: { balance[$0] < balance[$1] }) {
            let amount = min(-balance[debtor], balance[creditor])
            transfers.append(Transfer(from: debtor, to: creditor, points: amount))
            balance[debtor] += amount
            balance[creditor] -= amount
        }
        return transfers
    }

    /// 名次：分数从高到低的玩家下标。
    public static func ranking(scores: [Int]) -> [Int] {
        scores.indices.sorted { (scores[$0], -$0) > (scores[$1], -$1) }
    }
}
