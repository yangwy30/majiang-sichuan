import SwiftUI
import MajiangKit

/// 桌规表单：一行一项，左边名字和一句白话，右边大数字。跟标准血战一样的值是灰色细体，改过的是墨色。
struct HouseRulesForm: View {
    @Binding var rules: GameRules
    /// 已经打了几局：中途改规则时，总局数不能少于这个。
    var playedHands = 0
    /// 截图用：一打开就点开这一项。
    var opening: RuleItem?

    @State private var picking: RuleItem?
    @State private var showMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PresetTabs(rules: $rules)

            VStack(spacing: 0) {
                ForEach(RuleItem.main) { item in
                    RuleRow(item: item, rules: rules, large: true) { picking = item }
                }
            }
            .padding(.top, 4)

            Text(example)
                .font(.system(size: 14))
                .foregroundStyle(Theme.gray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { showMore.toggle() }
            } label: {
                HStack {
                    Text(moreLabel)
                    Spacer()
                    Text(showMore ? "收起" : "›")
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.text(size: 14))
            .padding(.top, 14)

            if showMore {
                VStack(spacing: 0) {
                    Hairline()
                    ForEach(RuleItem.more) { item in
                        RuleRow(item: item, rules: rules, large: false) { picking = item }
                    }
                }
            }
        }
        .sheet(item: $picking) { item in
            RulePicker(item: item, rules: $rules, playedHands: playedHands)
        }
        .onAppear {
            showMore = RuleItem.more.contains { !$0.isStandard(rules) }
            if let opening { picking = opening }
        }
    }

    private var moreLabel: String {
        let changed = RuleItem.more.filter { !$0.isStandard(rules) }.count
        return changed > 0 ? "更多桌规 · 改过 \(changed) 项" : "更多桌规"
    }

    /// 随改随算的示例句。
    private var example: String {
        let fan = rules.cappedFan(2)
        let mult = Payment.multiplier(totalFan: 2, isSelfDrawn: true, rules: rules)
        let each = mult * rules.basePoints
        let total = each * 3
        let money = (Double(total) * rules.yuanPerPoint).formatted(.number.precision(.fractionLength(0...2)))
        return "比如清一色自摸（\(fan) 番）：三家各付 \(each) 分，共赢 \(total) 分，折合 \(money) 元。"
    }
}

// MARK: - 预设

/// 「标准血战」「血流成河」，改过就多出一个「自己定」。换预设不动每分汇率。
private struct PresetTabs: View {
    @Binding var rules: GameRules

    private var current: Int {
        rules.scoresLike(.standard) ? 0 : rules.scoresLike(.xueliu) ? 1 : 2
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                tab("标准血战", index: 0, preset: .standard)
                tab("血流成河", index: 1, preset: .xueliu)
                if current == 2 { tab("自己定", index: 2, preset: nil) }
                Spacer()
            }
            Hairline()
        }
        .animation(.easeOut(duration: 0.15), value: current)
    }

    private func tab(_ label: String, index: Int, preset: GameRules?) -> some View {
        let on = current == index
        return Button {
            guard var preset else { return }
            preset.yuanPerPoint = rules.yuanPerPoint
            rules = preset
        } label: {
            Text(label)
                .font(.system(size: 15, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Theme.ink : Theme.gray)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(on ? Theme.ink : .clear).frame(height: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - 一行

private struct RuleRow: View {
    var item: RuleItem
    var rules: GameRules
    var large: Bool
    var action: () -> Void

    var body: some View {
        let value = item.value(rules)
        let standard = item.isStandard(rules)
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.system(size: 16))
                        if large {
                            Text(item.hint)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.gray)
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value.text)
                            .font(large ? .system(size: value.isNumber ? 34 : 20, weight: standard ? .thin : .light)
                                    .monospacedDigit()
                                  : .system(size: 16, weight: standard ? .regular : .medium))
                        if !value.unit.isEmpty {
                            Text(value.unit).font(.system(size: 14))
                        }
                    }
                    .foregroundStyle(standard ? Theme.gray : Theme.ink)
                }
                .frame(minHeight: large ? 84 : 56)
                Hairline()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("点一下改")
    }
}

// MARK: - 选项

private struct RulePicker: View {
    @Environment(\.dismiss) private var dismiss
    var item: RuleItem
    @Binding var rules: GameRules
    var playedHands: Int
    @State private var customYuan = ""

    var body: some View {
        let options = item.options(playedHands: playedHands, current: rules)
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(.system(size: 17, weight: .semibold))
                .padding(.top, 30)
            Text(item.note)
                .font(.system(size: 14))
                .foregroundStyle(Theme.gray)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 10)

            ForEach(options) { option in
                let selected = option.isSelected(rules)
                Button {
                    option.apply(&rules)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text(option.label)
                            .font(.system(size: 17, weight: selected ? .semibold : .regular))
                        Spacer()
                        if let tag = option.tag {
                            Text(tag).font(.system(size: 14)).foregroundStyle(Theme.gray)
                        }
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .opacity(selected ? 1 : 0)
                    }
                    .frame(height: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!option.enabled)
                .opacity(option.enabled ? 1 : 0.35)
                .accessibilityAddTraits(selected ? .isSelected : [])
                Hairline(color: Theme.lineSoft)
            }

            if item == .rate {
                HStack {
                    Text("其他").font(.system(size: 17))
                    Spacer()
                    TextField("填一个数", text: $customYuan)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("元").foregroundStyle(Theme.gray)
                }
                .frame(height: 52)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.ink)
        .presentationDetents([.height(height(options.count))])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(Theme.white)
        .onChange(of: customYuan) { _, text in
            if let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 {
                rules.yuanPerPoint = value
            }
        }
    }

    private func height(_ count: Int) -> CGFloat {
        CGFloat(110 + (count + (item == .rate ? 1 : 0)) * 53)
    }
}

// MARK: - 规则项

enum RuleItem: String, Identifiable, CaseIterable {
    case mode, cap, zimo, rate, rounds
    case dianGangHua, menQing, zhongZhang, base, penalty

    var id: String { rawValue }

    static let main: [RuleItem] = [.mode, .cap, .zimo, .rate, .rounds]
    static let more: [RuleItem] = [.dianGangHua, .menQing, .zhongZhang, .base, .penalty]

    var title: String {
        switch self {
        case .mode: return "玩法"
        case .cap: return "封顶"
        case .zimo: return "自摸"
        case .rate: return "1 分算"
        case .rounds: return "局数"
        case .dianGangHua: return "点杠花"
        case .menQing: return "门清"
        case .zhongZhang: return "中张（断幺九）"
        case .base: return "底分"
        case .penalty: return "诈胡罚分"
        }
    }

    var hint: String {
        switch self {
        case .mode: return "血战到底胡 3 家结手，血流成河胡后继续打"
        case .cap: return "每番翻倍，封顶防止一把输太多"
        case .zimo: return "成都主流自摸加底（+1 倍），也可设自摸加番"
        case .rate: return "结算时每 1 分折合多少元"
        case .rounds: return "整场一共打几局"
        case .dianGangHua, .menQing, .zhongZhang, .base, .penalty: return ""
        }
    }

    var note: String {
        switch self {
        case .mode: return "血战到底：一家胡牌后离场，剩下的人继续打直到 3 人胡牌或摸完；血流成河：胡牌后手牌锁定继续摸打，一局可连胡多次。"
        case .cap: return "川麻按 2 的番数次方翻倍。3 番 8 倍、4 番 16 倍（最常见）、5 番 32 倍。"
        case .zimo: return "自摸加底：总倍数 +1（如平胡自摸 2 倍、清一色自摸 5 倍）；自摸加番：总番数 +1（翻倍）。"
        case .rate: return "每桌自己定，换预设不会动这一项。比如 1 分 2 元时，赢 10 分就是 20 元。"
        case .rounds: return "朋友局常打 8 局或 12 局，也可以打完随时提前结算。"
        case .dianGangHua: return "别人打出牌被你直杠后补牌自摸：算自摸则三家都付；算点炮则点杠那一家包付。"
        case .menQing: return "开启后，整手牌不碰不明杠（暗杠不算破门清）额外加 1 番。"
        case .zhongZhang: return "开启后，整手牌全部由 2–8 组成（没有一、九）额外加 1 番。"
        case .base: return "默认 1 分/底，直杠和暗杠 2 倍底，巴杠 1 倍底。"
        case .penalty: return "推倒了却没缺门或凑不成胡牌，赔在场其余每家这么多分，这一局接着打。"
        }
    }

    func isStandard(_ rules: GameRules) -> Bool {
        let standard = GameRules.standard
        switch self {
        case .mode: return rules.mode == standard.mode
        case .cap: return rules.fanCap == standard.fanCap
        case .zimo: return rules.zimoRule == standard.zimoRule
        case .rate: return rules.yuanPerPoint == standard.yuanPerPoint
        case .rounds: return rules.totalHands == standard.totalHands
        case .dianGangHua: return rules.dianGangHuaRule == standard.dianGangHuaRule
        case .menQing: return rules.allowMenQing == standard.allowMenQing
        case .zhongZhang: return rules.allowZhongZhang == standard.allowZhongZhang
        case .base: return rules.basePoints == standard.basePoints
        case .penalty: return rules.falseWinPenalty == standard.falseWinPenalty
        }
    }

    func value(_ rules: GameRules) -> (text: String, unit: String, isNumber: Bool) {
        switch self {
        case .mode: return (rules.mode.name, "", false)
        case .cap:
            if rules.fanCap == 0 { return ("不封顶", "", false) }
            return ("\(rules.fanCap)番(\(1 << rules.fanCap)倍)", "", false)
        case .zimo: return (rules.zimoRule.name, "", false)
        case .rate: return (rules.yuanPerPoint.cleanNumber, "元", true)
        case .rounds: return ("\(rules.totalHands)", "局", true)
        case .dianGangHua: return (rules.dianGangHuaRule == .asZimo ? "算自摸" : "算点炮", "", false)
        case .menQing: return (rules.allowMenQing ? "+1 番" : "不计", "", false)
        case .zhongZhang: return (rules.allowZhongZhang ? "+1 番" : "不计", "", false)
        case .base: return ("\(rules.basePoints)", "分", true)
        case .penalty: return ("\(rules.falseWinPenalty)", "分", true)
        }
    }

    func options(playedHands: Int, current: GameRules) -> [RuleOption] {
        switch self {
        case .mode:
            return [
                RuleOption(label: "血战到底", tag: "成都标准", isSelected: { $0.mode == .xuezhan }, apply: { $0.mode = .xuezhan }),
                RuleOption(label: "血流成河", tag: "可连胡多次", isSelected: { $0.mode == .xueliu }, apply: { $0.mode = .xueliu }),
            ]
        case .cap:
            return [
                RuleOption(label: "3 番（8 倍）", tag: "小封顶", isSelected: { $0.fanCap == 3 }, apply: { $0.fanCap = 3 }),
                RuleOption(label: "4 番（16 倍）", tag: "成都主流", isSelected: { $0.fanCap == 4 }, apply: { $0.fanCap = 4 }),
                RuleOption(label: "5 番（32 倍）", tag: "大封顶", isSelected: { $0.fanCap == 5 }, apply: { $0.fanCap = 5 }),
                RuleOption(label: "不封顶", tag: nil, isSelected: { $0.fanCap == 0 }, apply: { $0.fanCap = 0 }),
            ]
        case .zimo:
            return [
                RuleOption(label: "自摸加底", tag: "总倍数 +1 · 主流", isSelected: { $0.zimoRule == .addDi }, apply: { $0.zimoRule = .addDi }),
                RuleOption(label: "自摸加番", tag: "番数 +1（翻倍）", isSelected: { $0.zimoRule == .addFan }, apply: { $0.zimoRule = .addFan }),
            ]
        case .rate:
            let rates: [Double] = [0.5, 1, 2, 5, 10]
            return rates.map { r in
                RuleOption(
                    label: "1 分算 \(r.cleanNumber) 元",
                    tag: r == 1 ? "默认" : nil,
                    isSelected: { $0.yuanPerPoint == r },
                    apply: { $0.yuanPerPoint = r }
                )
            }
        case .rounds:
            return [4, 8, 12, 16].map { n in
                RuleOption(
                    label: "\(n) 局",
                    tag: n == 8 ? "默认" : nil,
                    enabled: n > playedHands,
                    isSelected: { $0.totalHands == n },
                    apply: { $0.totalHands = n }
                )
            }
        case .dianGangHua:
            return [
                RuleOption(label: "点杠花算自摸", tag: "三家付 · 主流", isSelected: { $0.dianGangHuaRule == .asZimo }, apply: { $0.dianGangHuaRule = .asZimo }),
                RuleOption(label: "点杠花算点炮", tag: "点杠者一家付", isSelected: { $0.dianGangHuaRule == .asDianPao }, apply: { $0.dianGangHuaRule = .asDianPao }),
            ]
        case .menQing:
            return [
                RuleOption(label: "不计门清", tag: "标准血战", isSelected: { !$0.allowMenQing }, apply: { $0.allowMenQing = false }),
                RuleOption(label: "门清 +1 番", tag: nil, isSelected: { $0.allowMenQing }, apply: { $0.allowMenQing = true }),
            ]
        case .zhongZhang:
            return [
                RuleOption(label: "不计中张", tag: "标准血战", isSelected: { !$0.allowZhongZhang }, apply: { $0.allowZhongZhang = false }),
                RuleOption(label: "中张（断幺九）+1 番", tag: nil, isSelected: { $0.allowZhongZhang }, apply: { $0.allowZhongZhang = true }),
            ]
        case .base:
            return [1, 2, 5, 10].map { b in
                RuleOption(
                    label: "每底 \(b) 分",
                    tag: b == 1 ? "默认" : nil,
                    isSelected: { $0.basePoints == b },
                    apply: { $0.basePoints = b }
                )
            }
        case .penalty:
            return [8, 16, 32].map { p in
                RuleOption(
                    label: "赔每家 \(p) 分",
                    tag: p == 16 ? "默认" : nil,
                    isSelected: { $0.falseWinPenalty == p },
                    apply: { $0.falseWinPenalty = p }
                )
            }
        }
    }
}

struct RuleOption: Identifiable {
    let id = UUID()
    var label: String
    var tag: String?
    var enabled = true
    var isSelected: (GameRules) -> Bool
    var apply: (inout GameRules) -> Void
}
