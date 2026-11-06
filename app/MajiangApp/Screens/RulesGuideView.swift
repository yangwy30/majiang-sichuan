import SwiftUI
import MajiangKit

/// 规则和役种说明：给打立直日麻的人看的白话速查表。
struct RulesGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private let basics: [(String, String)] = [
        ("怎么算点和钱", "按翻数和符数算出基本点：闲家荣和由点炮者付 4 倍基本点，闲家自摸由庄家付 2 倍、另外两家闲家各付 1 倍；庄家和牌是闲家的 1.5 倍（荣和 6 倍，自摸三家各付 2 倍），全部按百位向上进位。5 翻起固定为满贯（闲 8000 / 庄 12000）、跳满、倍满、三倍满、役满。"),
        ("1 翻起和（无役不能和）", "立直麻将至少要有 1 翻「役」才能和牌。表宝牌、赤宝牌、里宝牌每张加 1 翻，但不能当起和役。没吃碰明杠（门前清）听牌时宣布「立直」，就有 1 翻役。"),
        ("副露减翻与门前限定", "立直、一发、门前清自摸和、平和、一杯口、二杯口、七对子只能在门前清（没吃、没碰、没明杠）时成立；三色同顺、一气通贯、混全带幺九、纯全带幺九、混一色、清一色在吃碰明杠后减 1 翻。"),
        ("半庄与东风战", "标准半庄打东场 4 局 + 南场 4 局共 8 局；东风战打 4 局。随时也可以提前结束结算。"),
        ("错和罚符", "推倒了却无役或凑不成和牌，赔另外三家各 3000 点，这一局接着打。"),
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
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if group.points == 13 {
                                Text("役满").font(Theme.serif(24, semibold: true))
                                Text("· 13 翻").font(.system(size: 15)).foregroundStyle(Theme.gray)
                            } else {
                                Text("\(group.points)").font(Theme.score(28))
                                Text("翻").font(Theme.serif(15))
                            }
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
            .navigationTitle("立直规则与役种")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose("关闭") { dismiss() }
            }
        }
    }
}
