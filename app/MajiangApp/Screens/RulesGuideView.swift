import SwiftUI
import MajiangKit

/// 四川麻将（血战到底 / 血流成河）规则与番种白话速查表。
struct RulesGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let basics: [(String, String)] = [
        ("108 张牌与定缺（缺一门）", "四川麻将仅使用万、条（索）、筒（饼）三门序数牌共 108 张，无东南西北中发白字牌、无花牌，且不可吃牌（只能碰、杠）。胡牌或听牌（下叫）时手牌最多只能包含 2 种花色；若三门花色俱全则称为「花猪」，不能胡牌。"),
        ("番数与倍数（2^番数）", "平胡 0 番为 1 倍底分；每增加 1 番翻一倍（1 番=2 倍，2 番=4 倍，3 番=8 倍，4 番=16 倍，5 番=32 倍）。「自摸加底」在总倍数上 +1，「自摸加番」则将总番数 +1 再翻倍。"),
        ("什么是「根」（每根 +1 番）", "整手牌中（不论是手牌里的四张、碰出去的三张加手里第四张、还是已经开杠的四张），只要有 4 张相同的牌就算 1 根，每根 +1 番。注：龙七对自带的第 1 根已计入 3 番，不重复加番；双龙七对额外 +1 番。"),
        ("刮风下雨与呼叫转移", "局内开杠立即收钱：直杠（点杠）收点杠者 2 倍底分；巴杠（弯杠/加杠）收在场未胡每家 1 倍底分；下雨（暗杠）收在场未胡每家 2 倍底分。若开杠后打出的牌点炮（杠上炮），触发「呼叫转移」，刚才那一笔杠收到的钱原封不动转给胡牌者。"),
        ("荒庄流局：退税 + 查花猪 + 查大叫", "牌墙摸完仍有人未胡时进入荒庄查叫：\n1. 自动退税：凡是未下叫（未听牌）或花猪的玩家，本局内收到的所有刮风下雨杠钱自动原路退回给支付者；\n2. 查花猪：三门俱全的花猪玩家，直接按封顶番数赔给所有非花猪在场玩家；\n3. 查大叫：未下叫玩家向已下叫玩家按其「大叫（最高可能胡牌番数）」赔付。"),
    ]

    private var groups: [(points: Int, fans: [Fan])] {
        Dictionary(grouping: Fan.allCases, by: \.points)
            .map { ($0.key, $0.value) }
            .sorted { $0.points < $1.points }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(basics, id: \.0) { title, text in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.system(size: 16, weight: .semibold))
                            Text(text)
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12)
                    }

                    ForEach(groups, id: \.points) { group in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(group.points)").font(Theme.score(28))
                            Text("番").font(Theme.serif(15))
                            Text("· \(1 << group.points) 倍")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.gray)
                        }
                        .padding(.top, 28)
                        .padding(.bottom, 4)
                        ForEach(group.fans, id: \.self) { fan in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fan.name).font(.system(size: 16, weight: .medium))
                                Text(fan.explanation)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.gray)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 11)
                            .overlay(alignment: .top) { Hairline() }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .page()
            .navigationTitle("四川麻将规则与番种")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose("关闭") { dismiss() }
            }
        }
    }
}
