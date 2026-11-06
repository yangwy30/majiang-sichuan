import SwiftUI
import MajiangKit

/// 桌规表单：一行一项，左边名字和一句白话，右边大数字。跟标准半庄一样的值是灰色细体，改过的是墨色。
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
        let han = rules.cappedFan(5)
        let deltas = Payment.winDeltas(winner: 1, discarder: 0, dealer: 0, totalFan: han, fu: 30, rules: rules)
        let points = deltas[1]
        let money = ((Double(points) / 1000.0) * rules.yuanPerPoint).formatted(.number.precision(.fractionLength(0...2)))
        return "比如闲家满贯（5 翻）：赢 \(points) 点，折合 \(money) 元。"
    }
}

// MARK: - 预设

/// 「标准半庄」「东风战」，改过就多出一个「自己定」。换预设不动千点汇率。
private struct PresetTabs: View {
    @Binding var rules: GameRules

    private var current: Int {
        rules.scoresLike(.standard) ? 0 : rules.scoresLike(.beginner) ? 1 : 2
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                tab("标准半庄", index: 0, preset: .standard)
                tab("东风战", index: 1, preset: .beginner)
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
    case rate, rounds, minimum, flowers, base
    case cap, penalty, swap

    var id: String { rawValue }

    static let main: [RuleItem] = [.rate, .rounds, .minimum, .flowers, .base]
    static let more: [RuleItem] = [.cap, .penalty, .swap]

    var title: String {
        switch self {
        case .rate: return "1000 点算"
        case .rounds: return "局制"
        case .minimum: return "起和"
        case .flowers: return "宝牌"
        case .base: return "切上满贯"
        case .cap: return "封顶"
        case .penalty: return "错和罚符"
        case .swap: return "每圈换座"
        }
    }

    var hint: String {
        switch self {
        case .rate: return "结算时每 1000 点折合多少元"
        case .rounds: return "半庄 8 局，东风战 4 局"
        case .minimum: return "至少几翻役才能和（宝牌不算）"
        case .flowers: return "表宝、赤宝、里宝每张 1 翻"
        case .base: return "30 符 4 翻、60 符 3 翻按满贯算"
        case .cap, .penalty, .swap: return ""
        }
    }

    var note: String {
        switch self {
        case .rate: return "每桌自己定，换预设不会动这一项。比如千点 1 元时，满贯 8000 点就是 8 元。"
        case .rounds: return "标准半庄打东场 4 局 + 南场 4 局共 8 局；时间紧可以打东风战 4 局。"
        case .minimum: return "立直麻将标准为 1 翻起和（宝牌不算役）。少数桌规要求 2 翻起和。"
        case .flowers: return "计入宝牌时，表宝牌、赤宝牌、里宝牌每张加 1 翻，但不计入 1 翻起和条件。"
        case .base: return "标准规则下 30 符 4 翻和 60 符 3 翻是 7700 / 11600 点；开启切上满贯后直接按满贯 8000 / 12000 点算。"
        case .cap: return "默认 13 翻及以上算累计役满。怕一把输太多可以设倍满（8 翻）或满贯（5 翻）封顶。"
        case .penalty: return "推倒了却无役或凑不成和牌，赔另外三家各这么多点，这一局接着打。"
        case .swap: return "朋友局一般不换座。"
        }
    }

    func isStandard(_ rules: GameRules) -> Bool {
        let standard = GameRules.standard
        switch self {
        case .rate: return rules.yuanPerPoint == standard.yuanPerPoint
        case .rounds: return rules.totalHands == standard.totalHands
        case .minimum: return rules.minimumFan == standard.minimumFan
        case .flowers: return rules.includeFlowers == standard.includeFlowers
        case .base: return rules.kiriageMangan == standard.kiriageMangan
        case .cap: return rules.fanCap == standard.fanCap
        case .penalty: return rules.falseWinPenalty == standard.falseWinPenalty
        case .swap: return rules.swapSeatsEachRound == standard.swapSeatsEachRound
        }
    }

    func value(_ rules: GameRules) -> (text: String, unit: String, isNumber: Bool) {
        switch self {
        case .rate: return (rules.yuanPerPoint.yuanText, "元", true)
        case .rounds:
            if rules.totalHands == 8 { return ("半庄 8 局", "", false) }
            if rules.totalHands == 4 { return ("东风 4 局", "", false) }
            return ("\(rules.totalHands)", "局", true)
        case .minimum: return ("\(rules.minimumFan)", "翻", true)
        case .flowers: return (rules.includeFlowers ? "计宝牌" : "不计", "", false)
        case .base: return (rules.kiriageMangan ? "开启" : "不切上", "", false)
        case .cap: return rules.fanCap > 0 ? ("\(rules.fanCap) 翻", "", false) : ("不封顶", "", false)
        case .penalty: return ("\(rules.falseWinPenalty) 点", "", false)
        case .swap: return (rules.swapSeatsEachRound ? "换" : "不换", "", false)
        }
    }

    func options(playedHands: Int, current: GameRules) -> [RuleOption] {
        switch self {
        case .rate:
            var values = [0.5, 1, 2, 5, 10]
            if !values.contains(current.yuanPerPoint) { values.append(current.yuanPerPoint); values.sort() }
            return values.map { RuleOption.choice(\.yuanPerPoint, $0, "\($0.yuanText) 元", marksStandard: false) }
        case .rounds:
            return [(8, "半庄战（东南 8 局）"), (4, "东风战（4 局）"), (16, "一庄战（16 局）")].map { hands, label in
                var option = RuleOption.choice(\.totalHands, hands, label)
                option.enabled = hands >= playedHands
                return option
            }
        case .minimum:
            return [1, 2].map { RuleOption.choice(\.minimumFan, $0, "\($0) 翻起和") }
        case .flowers:
            return [true, false].map { RuleOption.choice(\.includeFlowers, $0, $0 ? "计宝牌" : "不计宝牌") }
        case .base:
            return [false, true].map {
                RuleOption.choice(\.kiriageMangan, $0, $0 ? "切上满贯（按 8000 / 12000 算）" : "按实算（7700 / 11600 点）")
            }
        case .cap:
            return [(0, "不封顶（13 翻累计役满）"), (13, "13 翻（役满封顶）"), (8, "8 翻（倍满封顶）"), (5, "5 翻（满贯封顶）")].map {
                RuleOption.choice(\.fanCap, $0.0, $0.1)
            }
        case .penalty:
            var values = [3000, 2000, 4000]
            if !values.contains(current.falseWinPenalty) { values.append(current.falseWinPenalty) }
            return values.map { RuleOption.choice(\.falseWinPenalty, $0, "每家 \($0) 点") }
        case .swap:
            return [false, true].map { RuleOption.choice(\.swapSeatsEachRound, $0, $0 ? "换座" : "不换") }
        }
    }
}

struct RuleOption: Identifiable {
    var label: String
    var tag: String?
    var isSelected: (GameRules) -> Bool
    var apply: (inout GameRules) -> Void
    var enabled = true

    var id: String { label }

    static func choice<T: Equatable>(_ keyPath: WritableKeyPath<GameRules, T>, _ value: T, _ label: String,
                                     tag: String? = nil, marksStandard: Bool = true) -> RuleOption {
        let isStandard = marksStandard && GameRules.standard[keyPath: keyPath] == value
        return RuleOption(label: label, tag: isStandard ? "标准" : tag,
                          isSelected: { $0[keyPath: keyPath] == value },
                          apply: { $0[keyPath: keyPath] = value })
    }
}

extension Double {
    var yuanText: String { formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
}
