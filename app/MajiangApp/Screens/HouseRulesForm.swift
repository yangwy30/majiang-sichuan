import SwiftUI
import MajiangKit

/// 开局页和牌桌「改这场规则」共用的四川麻将家规表单。
struct HouseRulesForm: View {
    @Binding var rules: GameRules
    var playedHands: Int = 0

    private enum RuleItem: Identifiable {
        case mode, fanCap, zimoRule, dianGangHua, menQingZhongZhang, basePoints, yuanPerPoint, totalHands
        var id: Self { self }
    }

    @State private var picking: RuleItem?

    private struct Preset {
        var name: String
        var note: String
        var rules: GameRules
    }

    private let presets: [Preset] = [
        Preset(name: "成都血战", note: "4番封顶 · 自摸加底 · 三家胡完结局", rules: .standard),
        Preset(name: "血流成河", note: "4番封顶 · 自摸加底 · 一局可胡多次", rules: .xueliu),
        Preset(name: "血战加番", note: "5番封顶 · 自摸加番 · 算门清中张", rules: .highCap),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            presetRow

            VStack(spacing: 0) {
                ruleRow("玩法模式", value: rules.mode.name) { picking = .mode }
                Hairline()
                ruleRow("封顶番数", value: fanCapText(rules.fanCap)) { picking = .fanCap }
                Hairline()
                ruleRow("自摸算法", value: rules.zimoRule.name) { picking = .zimoRule }
                Hairline()
                ruleRow("点杠花", value: rules.dianGangHuaRule.name) { picking = .dianGangHua }
                Hairline()
                ruleRow("门清 / 中张", value: menQingZhongZhangText) { picking = .menQingZhongZhang }
                Hairline()
                ruleRow("每底几分", value: "\(rules.basePoints) 分") { picking = .basePoints }
                Hairline()
                ruleRow("1 分几元", value: "\(rules.yuanPerPoint.cleanNumber) 元") { picking = .yuanPerPoint }
                Hairline()
                ruleRow("本场局数", value: "\(rules.totalHands) 局") { picking = .totalHands }
            }
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
            .padding(.top, 14)

            Text(rules.summary)
                .font(.system(size: 14))
                .foregroundStyle(Theme.gray)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $picking) { item in
            pickerSheet(for: item)
        }
        .task {
            #if DEBUG
            if DemoScreen.current == .rulePicker, picking == nil { picking = .fanCap }
            #endif
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.name) { preset in
                let selected = rules.scoresLike(preset.rules)
                Button {
                    var next = preset.rules
                    next.yuanPerPoint = rules.yuanPerPoint
                    rules = next
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                            .font(.system(size: 15, weight: .medium))
                        Text(preset.note)
                            .font(.system(size: 12))
                            .foregroundStyle(selected ? .white.opacity(0.75) : Theme.gray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(selected ? .white : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(selected ? Theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? Theme.ink : Theme.line)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func ruleRow(_ label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 16))
                Spacer()
                Text(value)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.gray)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fanCapText(_ cap: Int) -> String {
        cap == 0 ? "不封顶" : "\(cap) 番（\(1 << cap) 倍）"
    }

    private var menQingZhongZhangText: String {
        switch (rules.allowMenQing, rules.allowZhongZhang) {
        case (false, false): return "不计"
        case (true, false): return "只算门清 (+1番)"
        case (false, true): return "只算中张 (+1番)"
        case (true, true): return "门清 + 中张 (各+1番)"
        }
    }

    @ViewBuilder
    private func pickerSheet(for item: RuleItem) -> some View {
        switch item {
        case .mode:
            RulePickerSheet(
                title: "玩法模式",
                options: [
                    (SichuanMode.xuezhan, "血战到底", "1 家胡牌后离场，剩下玩家继续打，只向在场未胡玩家收钱；最多 3 家胡牌或摸完荒庄查大叫"),
                    (SichuanMode.xueliu, "血流成河", "胡牌后不离场，锁住手牌继续摸打，一局内可以连续胡多次，直到牌墙摸完再查大叫退税"),
                ],
                selection: $rules.mode
            )
        case .fanCap:
            RulePickerSheet(
                title: "封顶番数",
                options: [
                    (3, "3 番封顶（8 倍）", "满 3 番即封顶 8 倍，节奏明快，花猪赔 8 倍"),
                    (4, "4 番封顶（16 倍）", "成都茶馆最主流设置，满 4 番封顶 16 倍，花猪赔 16 倍"),
                    (5, "5 番封顶（32 倍）", "清龙七对、天胡等大牌可拿满 32 倍，花猪赔 32 倍"),
                    (0, "不封顶", "有多少番翻多少倍（2^番数），刺激局适用"),
                ],
                selection: $rules.fanCap
            )
        case .zimoRule:
            RulePickerSheet(
                title: "自摸算法",
                options: [
                    (ZimoRule.addDi, "自摸加底", "成都主流：自摸时在总倍数上 +1 底（例如平胡 0 番自摸每家付 1+1=2 倍，2 番自摸每家付 4+1=5 倍）"),
                    (ZimoRule.addFan, "自摸加番", "重庆/部分川南玩法：自摸直接 +1 番翻倍（例如平胡自摸算 1 番 2 倍，2 番自摸算 3 番 8 倍）"),
                ],
                selection: $rules.zimoRule
            )
        case .dianGangHua:
            RulePickerSheet(
                title: "点杠花（直杠补牌胡）",
                options: [
                    (DianGangHuaRule.asZimo, "点杠花算自摸", "别人打牌给你直杠，补张胡牌算自摸，在场未胡三家都要付钱"),
                    (DianGangHuaRule.asDianPao, "点杠花算点炮", "谁点的杠就由谁一家包付这把杠上花"),
                ],
                selection: $rules.dianGangHuaRule
            )
        case .menQingZhongZhang:
            let binding = Binding<Int>(
                get: {
                    switch (rules.allowMenQing, rules.allowZhongZhang) {
                    case (false, false): return 0
                    case (true, false): return 1
                    case (false, true): return 2
                    case (true, true): return 3
                    }
                },
                set: { val in
                    rules.allowMenQing = (val == 1 || val == 3)
                    rules.allowZhongZhang = (val == 2 || val == 3)
                }
            )
            RulePickerSheet(
                title: "门清 / 中张（断幺九）",
                options: [
                    (0, "不计门清中张", "传统老成都血战规则，门前清与断幺九不额外加番"),
                    (3, "门清 + 中张（各 +1 番）", "门前清（无碰无明杠）+1 番，全由 2~8 组成（无一、九）+1 番"),
                    (1, "只算门清（+1 番）", "门前清 +1 番，中张不加番"),
                    (2, "只算中张（+1 番）", "断幺九 +1 番，门前清不加番"),
                ],
                selection: binding
            )
        case .basePoints:
            RulePickerSheet(
                title: "每底几分",
                options: [
                    (1, "1 分底", "平胡 1 分，对对胡 2 分，清一色 4 分，直杠 2 分，巴杠 1 分，暗杠 2 分"),
                    (2, "2 分底", "所有番种与刮风下雨按 2 分底倍增"),
                    (5, "5 分底", "所有番种与刮风下雨按 5 分底倍增"),
                    (10, "10 分底", "所有番种与刮风下雨按 10 分底倍增"),
                ],
                selection: $rules.basePoints
            )
        case .yuanPerPoint:
            RulePickerSheet(
                title: "1 分几元",
                options: [
                    (0.5, "1 分 0.5 元", "5 毛底"),
                    (1.0, "1 分 1 元", "1 块底，分就是元"),
                    (2.0, "1 分 2 元", "2 块底"),
                    (5.0, "1 分 5 元", "5 块底"),
                    (10.0, "1 分 10 元", "10 块底"),
                ],
                selection: $rules.yuanPerPoint
            )
        case .totalHands:
            RulePickerSheet(
                title: "本场局数",
                options: [
                    (4, "4 局（一圈）", "快速打 4 局"),
                    (8, "8 局（两圈）", "茶馆常规 8 局，随时也可提前结算"),
                    (12, "12 局（三圈）", "下午茶长局"),
                    (16, "16 局（四圈）", "完整四圈"),
                ],
                selection: $rules.totalHands
            )
        }
    }
}

private struct RulePickerSheet<Value: Hashable>: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var options: [(Value, String, String)]
    @Binding var selection: Value

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.0) { index, option in
                        if index > 0 { Hairline() }
                        Button {
                            selection = option.0
                            dismiss()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.1).font(.system(size: 16, weight: .medium))
                                    Text(option.2)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Theme.gray)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .opacity(selection == option.0 ? 1 : 0)
                            }
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .page()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
