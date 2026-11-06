import SwiftUI
import MajiangKit

/// 开局：第一行是自己，往下按出牌顺序填下家、对家、上家；第一局谁坐庄另外点（默认自己）。
/// 「我」和「第一局的庄」分开：牌桌图上自己总在最下面，首页历史显示自己的输赢。
/// 规则收成一行，一般设一次就不再改；填的 4 个人以前一起打过，就自动用上次那场的家规。
struct NewGameView: View {
    @Environment(AppModel.self) private var model
    @State private var names = ["", "", "", ""]
    /// 第一局坐庄的是第几行（0 是自己）。
    @State private var dealerRow = 0
    @State private var rules = GameRules()
    @State private var editingRules = false
    /// 规则是按这 4 个人上次那场自动带上的。
    @State private var rulesFromGroup = false
    /// 自己点开改过规则，就不再按名字自动换。
    @State private var rulesTouched = false
    @FocusState private var focused: Int?

    private var trimmed: [String] { names.map { $0.trimmingCharacters(in: .whitespaces) } }

    private var canStart: Bool {
        trimmed.allSatisfy { !$0.isEmpty } && Set(trimmed).count == 4
    }

    /// 不能开始时按钮上直接写原因。
    private var startLabel: String {
        if canStart { return "开始" }
        let filled = trimmed.filter { !$0.isEmpty }
        return Set(filled).count < filled.count ? "名字不能重复" : "填好 4 个名字"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageTitle(title: "谁在打？", subtitle: "第一行是你，往下按出牌顺序填。")

                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { i in
                        HStack(spacing: 14) {
                            // 门风跟着第一局的庄走：庄是东，往下南、西、北
                            Text(Wind(rawValue: (i - dealerRow + 4) % 4)!.name)
                                .font(Theme.serif(15))
                                .foregroundStyle(Theme.gray)
                                .frame(width: 22, alignment: .leading)
                            TextField(Self.seatHints[i], text: $names[i])
                                .font(.system(size: 17))
                                .focused($focused, equals: i)
                                .submitLabel(i < 3 ? .next : .done)
                                .onSubmit { focused = i < 3 ? i + 1 : nil }
                                .accessibilityLabel(Self.seatNames[i])
                            if i == dealerRow { DealerStamp() }
                        }
                        .frame(height: 58)
                        if i < 3 { Hairline(color: Theme.lineSoft) }
                    }
                }
                .block(radius: 22)
                .padding(.top, 28)

                SectionLabel("第一局谁坐庄")
                    .padding(.top, 24)
                    .padding(.bottom, 10)
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        ChoiceChip(title: trimmed[i].isEmpty ? Self.seatNames[i] : trimmed[i], selected: dealerRow == i) {
                            dealerRow = i
                        }
                    }
                }

                if !frequentNames.isEmpty {
                    SectionLabel("常一起打的")
                        .padding(.top, 28)
                        .padding(.bottom, 10)
                    FlowLayout(spacing: 8) {
                        ForEach(frequentNames, id: \.self) { name in
                            NameChip(name: name, selected: false) { add(name) }
                        }
                    }
                }

                Button {
                    editingRules = true
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("规则").font(.system(size: 16))
                            Spacer()
                            Text(rules.shortSummary + " ›")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.gray)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        if rulesFromGroup {
                            Text("上次跟这 4 位就这么打的")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.gray)
                        }
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 56)
                    .block(radius: 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 28)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .bottomBar {
            Button(startLabel) { start() }
            .buttonStyle(.primary)
            .disabled(!canStart)
        }
        .page()
        .navigationBarBackButtonHidden()
        .toolbar {
            NavBack("首页") { model.path.removeLast() }
        }
        .sheet(isPresented: $editingRules) {
            RulesSheet(rules: $rules, opening: model.demoScreen == .rulePicker ? .cap : nil)
        }
        .onAppear {
            // 第一行是自己：用上一场的名字先填上，常一起打的人就会往下填
            if names[0].isEmpty, let me = model.archive.lastMeName { names[0] = me }
            rules = model.archive.lastRules
            if model.demoScreen == .houseRules || model.demoScreen == .rulePicker {
                rules.fanCap = 64
                rules.yuanPerPoint = 2
                editingRules = true
            }
        }
        .onChange(of: trimmed) { _, names in
            guard !rulesTouched else { return }
            if let remembered = model.archive.lastRules(forPlayers: names) {
                rules = remembered
                rulesFromGroup = true
            } else if rulesFromGroup {
                rules = model.archive.lastRules
                rulesFromGroup = false
            }
        }
        .onChange(of: rules) {
            if editingRules {
                rulesTouched = true
                rulesFromGroup = false
            }
        }
    }

    private static let seatNames = ["你", "下家", "对家", "上家"]
    private static let seatHints = ["你的名字", "下家", "对家", "上家"]

    private var frequentNames: [String] {
        model.archive.frequentPlayers.map(\.name).filter { !trimmed.contains($0) }
    }

    /// 点一下常一起打的人，按顺序填进第一个空位。
    private func add(_ name: String) {
        if let i = trimmed.firstIndex(where: \.isEmpty) {
            names[i] = name
        }
    }

    private func start() {
        let known = Dictionary(model.archive.frequentPlayers.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        // 存的时候从第一局的庄开始排（东南西北），记下自己是第几个
        let seated = (0..<4).map { trimmed[(dealerRow + $0) % 4] }
        let players = seated.map { known[$0] ?? Player(name: $0) }
        let game = model.startGame(players: players, me: (4 - dealerRow) % 4, rules: rules)
        model.path = [.table(game.id)]
    }
}

/// 规则：家规表单，开局时改。
private struct RulesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var rules: GameRules
    /// 截图用：一打开就点开这一项。
    var opening: RuleItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                HouseRulesForm(rules: $rules, opening: opening)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
            .page()
            .navigationTitle("规则")
            .navigationBarTitleDisplayMode(.inline)
            // 改了就生效，没有「取消」；底部的按钮收起来
            .bottomBar {
                Button("好") { dismiss() }
                    .buttonStyle(.primary)
            }
        }
        .presentationDetents([.large])
    }
}

/// 自动换行的横排（常用牌友标签用）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
