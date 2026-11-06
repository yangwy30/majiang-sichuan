import SwiftUI
import MajiangKit

/// 核对：一页里核对牌面、补上照片看不出来的（自摸还是点炮、少见情况、花牌）。
/// 拿不准的牌一次问一张；凑不成和牌时原地说最可能认错了哪张。
struct CheckView: View {
    @Environment(AppModel.self) private var model
    @Bindable var flow: RoundFlow
    var finish: (HandOutcome) -> Void

    @State private var editing: EditTarget?
    @State private var actionTile: Int?
    @State private var actionMeld: Int?
    @State private var confirmFalseWin = false
    @State private var rareOpen = false
    /// 牌一张张落进格子里（从拍照页升上来时）。
    @State private var landed = false
    /// 再认一遍时牌从这个时刻开始翻，等落定以后。
    @State private var flipStart = Date()
    /// 再认一遍等久了才给「不等了」。
    @State private var canSkip = false
    @State private var showPhoto = false
    @State private var showInvite = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum EditTarget: Identifiable {
        case replace(Int)
        case insert(after: Int)
        case add
        case meld

        var id: String {
            switch self {
            case .replace(let i): "replace-\(i)"
            case .insert(let i): "insert-\(i)"
            case .add: "add"
            case .meld: "meld"
            }
        }
    }

    private var game: Game { flow.game }
    private var winnerName: String { game.players[flow.winner].name }

    /// 这一页有多宽（不用屏幕宽度：Duo 分屏时窗口比屏幕窄）。
    @State private var pageWidth: CGFloat = 0

    /// 每行 7 张，按页面宽度算牌的大小，最大 44。宽屏上内容收在中间一栏，按那一栏算。
    private var tileWidth: CGFloat {
        guard pageWidth > 0 else { return 44 }
        return max(24, min(44, (min(pageWidth, Theme.columnWidth) - 48 - 6 * 6) / 7))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    PageTitle(title: "核对一下", subtitle: subtitle)
                    photoThumbnail
                }

                tileGrid.padding(.top, 22)
                // 教怎么用的说明句，记过几手以后就收起来
                if !flow.tiles.isEmpty && !model.isSeasoned {
                    Text(flow.isReviewing ? "最右边那张算和的牌。" : "最右边那张算和的牌。不对就点一下改。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                        .padding(.top, 6)
                }
                melds
                notes
                inviteLine

                if flow.isReviewing {
                    reviewingLine.padding(.top, 14)
                } else if let index = flow.firstPending {
                    QuestionCard(flow: flow, index: index) { editing = .replace(index) }
                        .padding(.top, 18)
                } else if !flow.tiles.isEmpty && !flow.isValidWin {
                    problemCard.padding(.top, 18)
                } else if flow.tiles.isEmpty {
                    // 手动输入还没加牌时，和错了也要能直接记
                    falseWinLink.padding(.top, 8)
                }

                howWon
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .bottomBar {
            Button {
                flow.showResult = true
            } label: {
                if let reason = flow.blockedReason {
                    Text(reason)
                } else if case .success(let result) = flow.scoring {
                    HStack(spacing: 10) {
                        Text("看结果")
                        Text("·").fontWeight(.light).opacity(0.7)
                        Text("\(result.totalFan) 翻 \(result.fu) 符").monospacedDigit()
                    }
                }
            }
            .buttonStyle(.primary)
            .disabled(flow.blockedReason != nil)
        }
        .page()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        // 核对页是从下面升上来盖住拍照页的，不在导航栈里，返回键自己放；
        // 系统在这里还会多画一个返回键（iOS 27 模拟器上看到的），藏掉
        .navigationBarBackButtonHidden()
        .toolbar {
            NavBack("重拍") { flow.steps.removeAll() }
        }
        .sheet(item: $editing) { target in sheet(for: target) }
        // 牌落进格子时很轻地震一下
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: landed) { _, new in new }
        .task {
            // 等页面升上来再落牌（onAppear 里直接改，第一帧还没画，看不到动画）
            flipStart = Date().addingTimeInterval(reduceMotion ? 0 : 1.3)
            try? await Task.sleep(for: .seconds(0.3))
            landed = true
        }
        .task(id: flow.isReviewing) {
            canSkip = false
            guard flow.isReviewing else { return }
            // 九成 16 秒内认完，12 秒还没好才给出口
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { canSkip = true }
        }
        .fullScreenCover(isPresented: $showPhoto) {
            if let photo = flow.photo {
                PhotoViewer(photo: photo) { showPhoto = false }
            }
        }
        .sheet(isPresented: $showInvite) { InviteView() }
        .sheet(isPresented: $flow.showResult) {
            ResultSheet(flow: flow, finish: finish)
        }
        .confirmationDialog(actionTitle, isPresented: Binding(get: { actionTile != nil }, set: { if !$0 { actionTile = nil } }),
                            titleVisibility: .visible, presenting: actionTile) { index in
            Button("换一张") { editing = .replace(index) }
            if index != winningIndex {
                Button("这张是和的那张") { flow.winningIndex = index }
            }
            Button("在后面加一张") { editing = .insert(after: index) }
            Button("删掉这张", role: .destructive) { flow.remove(at: index) }
        }
        .confirmationDialog("删掉这组？", isPresented: Binding(get: { actionMeld != nil }, set: { if !$0 { actionMeld = nil } }),
                            titleVisibility: .visible, presenting: actionMeld) { index in
            Button("删掉", role: .destructive) {
                if flow.melds.indices.contains(index) { flow.melds.remove(at: index) }
            }
        }
        .confirmationDialog(flow.winnerChosen ? "\(winnerName)和错了？" : "谁和错了？",
                            isPresented: $confirmFalseWin, titleVisibility: .visible) {
            if flow.winnerChosen {
                Button("记下：赔三家各 \(game.rules.falseWinPenalty) 分", role: .destructive) {
                    finish(.falseWin(offender: flow.winner))
                }
            } else {
                ForEach(0..<4, id: \.self) { i in
                    Button(game.players[i].name, role: .destructive) { finish(.falseWin(offender: i)) }
                }
            }
        } message: {
            Text("这一局不算打完，接着打。")
        }
        .onChange(of: flow.selfDrawn) { _, _ in
            // 换了自摸 / 点炮，不再可能的少见情况自动去掉
            flow.specials = flow.specials.filter { flow.isAvailable($0) }
        }
    }

    private var subtitle: String {
        let who = flow.winnerChosen ? "\(winnerName)和了 · " : ""
        if flow.source == "手动输入" { return who + "手动输入" }
        // 演示数据不看照片，一定要说清楚，不然会以为是认错了（截图模式除外）
        if flow.source == "演示" && DemoScreen.current == nil { return "演示数据，没看你的照片 · 长按首页标题填 Key" }
        let count = who + "认出 \(flow.hand.allTiles.count) 张"
        if flow.isReviewing { return count }
        if flow.source == "双读" {
            return count + (flow.reviewAtLoad == 0 ? " · 两遍读得一样" : " · \(flow.reviewAtLoad) 张两遍不一样")
        }
        return count
    }

    private var winningIndex: Int? { flow.winningIndex ?? flow.tiles.indices.last }

    private var actionTitle: String {
        guard let i = actionTile, flow.tiles.indices.contains(i) else { return "" }
        return "第 \(i + 1) 张 · \(flow.tiles[i].tile.displayName)"
    }

    // MARK: 照片

    /// 标题右边一张小图，点开全屏看：核对时要对照照片，不用退回去重拍。
    @ViewBuilder
    private var photoThumbnail: some View {
        if let photo = flow.photo {
            Button { showPhoto = true } label: {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel("看拍的照片")
        }
    }

    /// 没邀请码、用离线认牌时，这手牌要动手改过、牌也对了，才提一句 AI 认牌。拍照页不提，免得打扰。
    @ViewBuilder
    private var inviteLine: some View {
        if model.needsInvite && flow.source != "手动输入" && flow.corrections > 0
            && !flow.isReviewing && flow.firstPending == nil && flow.isValidWin {
            Button { showInvite = true } label: {
                Text("这手有 \(flow.corrections) 处要你动手改。有邀请码可以开 AI 认牌，更准 ›")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }

    // MARK: 牌面

    /// 不成和时最可能认错的那张，标成朱红虚线。
    private var suspect: Int? {
        guard flow.firstPending == nil, !flow.isValidWin else { return nil }
        return flow.suggestions.first?.index
    }

    private var canAddTile: Bool { flow.tiles.count + 3 * flow.melds.count < 14 }

    private var tileGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), alignment: .center, spacing: 10) {
            ForEach(Array(flow.tiles.enumerated()), id: \.element.id) { index, tile in
                Button {
                    actionTile = index
                } label: {
                    VStack(spacing: 4) {
                        FlippingTile(index: index, width: tileWidth, active: flow.isReviewing, start: flipStart) {
                            TileFace(tile: tile.tile, width: tileWidth,
                                     state: tile.needsReview ? .doubt : index == suspect ? .wrong : .normal)
                        }
                        // 和的那张下面盖一个朱红小印「和」
                        Group {
                            if index == winningIndex {
                                Seal(text: "和", size: 16).accessibilityLabel("和的那张")
                            } else {
                                Color.clear
                            }
                        }
                        .frame(height: 16)
                    }
                    // 「和」字跟着牌一起落
                    .opacity(landed || reduceMotion ? 1 : 0)
                    .offset(y: landed || reduceMotion ? 0 : -26)
                    .scaleEffect(landed || reduceMotion ? 1 : 0.86)
                    .animation(.spring(response: 0.42, dampingFraction: 0.68).delay(Double(index) * 0.05), value: landed)
                }
                .buttonStyle(.plain)
                .disabled(flow.isReviewing)
            }
            if canAddTile && !flow.isReviewing {
                Button {
                    editing = .add
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: tileWidth * 0.16, style: .continuous)
                            .strokeBorder(Theme.faint, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(width: tileWidth, height: (tileWidth * 1.32).rounded())
                            .overlay(Image(systemName: "plus").foregroundStyle(Theme.gray))
                        Color.clear.frame(height: 16)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("加一张")
            }
        }
    }

    /// 亮在桌上的牌（吃碰杠）。没有就只留一行小字入口。
    @ViewBuilder
    private var melds: some View {
        if flow.melds.isEmpty {
            if !flow.isReviewing {
                Button("有吃、碰、杠亮在桌上？加上 ›") { editing = .meld }
                    .buttonStyle(.text(size: 14))
            }
        } else {
            HStack {
                SectionLabel("亮在桌上的")
                Button("加一组 ›") { editing = .meld }
                    .buttonStyle(.text(size: 14))
                    .disabled(flow.isReviewing)
            }
            .padding(.top, 14)
            FlowLayout(spacing: 14) {
                ForEach(Array(flow.melds.enumerated()), id: \.offset) { index, meld in
                    Button {
                        actionMeld = index
                    } label: {
                        HStack(spacing: 2) {
                            ForEach(Array(meld.tiles.enumerated()), id: \.offset) { _, tile in
                                TileFace(tile: tile, width: 30)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(meld.kindName + meld.displayText)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// 识别时的说明（画面里有别的牌没算、副露两边读得不一样、Gemini 没复核上……）。
    @ViewBuilder
    private var notes: some View {
        if !flow.notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(flow.notes, id: \.self) { note in
                    Text(note)
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.gray)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        }
    }

    /// 第一遍已经读出来了，后台再认一遍：牌在上面翻，这里只说一句。
    private var reviewingLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("每张翻过来再认一遍，几秒就好。可以先选下面谁和的、怎么和的。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.gray)
                .fixedSize(horizontal: false, vertical: true)
            if canSkip {
                // 偶尔会卡到超时（一分钟），不让人干等
                Button("不等了，就用现在这些牌 ›") {
                    flow.cancelRecognition()
                    flow.notes.append("没等第二遍认完，只有第一遍的读法，对照照片看一眼")
                }
                .buttonStyle(.text(size: 14))
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: canSkip)
    }

    // MARK: 不成和

    private var problemCard: some View {
        let suggestion = flow.suggestions.first
        let minimum = game.rules.minimumFan
        var title = "还凑不成和牌"
        var reason: Text
        switch flow.scoring {
        case .success(let result):
            title = result.fanWithoutFlowers == 0
                ? "无役，立直麻将至少要有 \(minimum) 翻役才能和"
                : "只有 \(result.fanWithoutFlowers) 翻役，本场要 \(minimum) 翻才能和"
            reason = Text("牌型没问题。如果这手立直了，在下面「立直与特殊情况」里勾上「立直」；宝牌每张加 1 翻，但不算进起和役。")
        case .failure(.wrongTileCount):
            reason = Text("和牌一共 14 张（每个杠多 1 张），现在是 \(flow.hand.allTiles.count) 张。")
        case .failure(.tileMoreThanFour):
            reason = Text("\(flow.hand.overusedTiles.map(\.displayName).joined(separator: "、")) 超过了 4 张，一定有牌认错了。")
        case .failure:
            reason = Text("和牌要 4 面子加 1 雀头（或七对子、国士无双），这 \(flow.hand.allTiles.count) 张凑不出来。")
        }
        if let suggestion, let index = suggestion.index {
            reason = reason + Text("最可能是") + Text("第 \(index + 1) 张").fontWeight(.semibold).foregroundStyle(Theme.ink)
                + Text("认错了：改成 \(suggestion.to.displayName) 就能和。")
        } else if let suggestion {
            reason = reason + Text("好像少认了一张：补一张 \(suggestion.to.displayName) 就能和。")
        } else if case .failure = flow.scoring {
            reason = reason + Text(flow.photo == nil ? "改一张也凑不成，可能不止一张认错了，对照桌上的牌再看看。"
                                    : "改一张也凑不成，可能不止一张认错了，点右上角的照片对照着再看看。")
        }

        return VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 17, weight: .semibold))
            reason
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x3A3934))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let suggestion {
                HStack(spacing: 12) {
                    Button {
                        flow.apply(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            TileFace(tile: suggestion.to, width: 22)
                            Text(suggestion.index == nil ? "补一张 \(suggestion.to.displayName)" : "改成 \(suggestion.to.displayName)")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 18)
                        .frame(height: 44)
                        .foregroundStyle(.white)
                        .background(Theme.ink, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button("自己改") { editing = suggestion.index.map { .replace($0) } ?? .add }
                        .buttonStyle(.text)
                        .padding(.horizontal, 6)
                }
                .padding(.top, 16)
            }
            Hairline(color: Theme.lineSoft)
                .padding(.top, 16)
                .padding(.bottom, 12)
            falseWinLink
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .block()
    }

    private var falseWinLink: some View {
        Button {
            confirmFalseWin = true
        } label: {
            Text(flow.tiles.isEmpty ? "其实是和错了？记下来（赔三家各 \(game.rules.falseWinPenalty) 分）›"
                 : "牌没认错，是真的和错了？记下来（赔三家各 \(game.rules.falseWinPenalty) 分）›")
                .font(.system(size: 14))
                .foregroundStyle(Theme.gray)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: 怎么和的

    private var shapeBroken: Bool {
        if case .failure = flow.scoring { return true }
        return false
    }

    /// 谁和了、怎么和的：都不预先选。「怎么和的」一排四个：自摸，或者另外三个人谁点的炮，点一下两件事都说清。
    @ViewBuilder
    private var howWon: some View {
        SectionLabel("谁和了")
            .padding(.top, 28)
            .padding(.bottom, 10)
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                ChoiceChip(title: game.players[i].name, selected: flow.winnerChosen && flow.winner == i) {
                    flow.pickWinner(i)
                }
            }
        }

        SectionLabel("怎么和的")
            .padding(.top, 24)
            .padding(.bottom, 10)
        VStack(alignment: .leading, spacing: 0) {
            if flow.winnerChosen {
                HStack(spacing: 8) {
                    ChoiceChip(title: "自摸", selected: flow.wayChosen && flow.selfDrawn) { flow.pickSelfDrawn() }
                    ForEach((0..<4).filter { $0 != flow.winner }, id: \.self) { i in
                        ChoiceChip(title: "\(game.players[i].name)点炮",
                                   selected: flow.wayChosen && !flow.selfDrawn && flow.discarder == i) {
                            flow.pickDiscarder(i)
                        }
                    }
                }
            }
            if let wayNote {
                Text(wayNote)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, flow.winnerChosen ? 10 : 0)
            }
        }
        // 牌还凑不成和的时候，先改牌
        .opacity(shapeBroken ? 0.5 : 1)
        .disabled(shapeBroken)

        VStack(spacing: 0) {
            rareSection
            if game.rules.includeFlowers {
                Hairline(color: Theme.lineSoft)
                flowers
            }
        }
        .block()
        .padding(.top, 22)
    }

    private var wayNote: String? {
        if !flow.winnerChosen { return "先选上面谁和了。" }
        if model.isSeasoned { return nil }
        if !flow.wayChosen { return "自己摸到的选「自摸」；和的是别人打出的牌，就选打那张的人。" }
        if flow.selfDrawn { return "自己摸到和的那张，三家都要付。" }
        return "和的是\(flow.discarder.map { game.players[$0].name } ?? "别人")打出的牌。"
    }

    private var availableRare: [SpecialWin] { SpecialWin.allCases.filter { flow.isAvailable($0) } }

    @ViewBuilder
    private var rareSection: some View {
        let chosen = availableRare.filter { flow.specials.contains($0) }
        Button {
            withAnimation(.easeOut(duration: 0.2)) { rareOpen.toggle() }
        } label: {
            HStack {
                Text("立直与特殊情况").font(.system(size: 16))
                Spacer()
                Text((chosen.isEmpty ? "没有" : chosen.map(\.name).joined(separator: "、")) + (rareOpen ? " ⌃" : " ›"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.gray)
            }
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if rareOpen {
            ForEach(availableRare, id: \.self) { special in
                let on = flow.specials.contains(special)
                Button {
                    if on {
                        flow.specials.remove(special)
                    } else {
                        flow.specials.subtract(special.conflicts)
                        flow.specials.insert(special)
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            (Text(special.name) + Text(" · \(special.fanPoints) 翻").foregroundStyle(Theme.gray))
                                .font(.system(size: 15))
                            Text(special.plain)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.gray)
                        }
                        Spacer()
                        ZStack {
                            Circle().strokeBorder(Color(hex: 0xD6D2C7), lineWidth: 1.5).opacity(on ? 0 : 1)
                            Circle().fill(Theme.ink).opacity(on ? 1 : 0)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(on ? 1 : 0)
                        }
                        .frame(width: 24, height: 24)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Hairline(color: Theme.lineSoft) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var flowers: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("宝牌").font(.system(size: 16))
                if !model.isSeasoned {
                    Text("表宝、赤宝、里宝每张 1 翻，不算起和役").font(.system(size: 14)).foregroundStyle(Theme.gray)
                }
            }
            Spacer()
            HStack(spacing: 14) {
                stepButton("minus", label: "少一张") { flow.flowerCount = max(0, flow.flowerCount - 1) }
                    .disabled(flow.flowerCount == 0)
                Text("\(flow.flowerCount)")
                    .font(.system(size: 17).monospacedDigit())
                    .frame(minWidth: 14)
                stepButton("plus", label: "多一张") { flow.flowerCount = min(12, flow.flowerCount + 1) }
                    .disabled(flow.flowerCount == 12)
            }
        }
        .frame(minHeight: 60)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32)
                .overlay(Circle().strokeBorder(Theme.line))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: 改牌

    @ViewBuilder
    private func sheet(for target: EditTarget) -> some View {
        switch target {
        case .replace(let index) where flow.tiles.indices.contains(index):
            TileEditSheet(title: "第 \(index + 1) 张是", current: flow.tiles[index].tile) { flow.choose($0, at: index) }
        case .insert(let index):
            TileEditSheet(title: "在第 \(index + 1) 张后面加", current: nil) { flow.insert($0, after: index) }
        case .add:
            TileEditSheet(title: "加一张", current: nil) { flow.append($0) }
        case .meld:
            MeldEditSheet { flow.melds.append($0) }
        default:
            EmptyView()
        }
    }
}

/// 拿不准的一张：「第 13 张看不太清，是哪个？」，候选旁边说选了能不能和。
/// 只有一边读到的牌问「照片里有这张吗」，多一个「没有这张」。
private struct QuestionCard: View {
    var flow: RoundFlow
    var index: Int
    var other: () -> Void

    private var tile: RecognizedTile { flow.tiles[index] }
    private var candidates: [Tile] { Array(tile.candidates.prefix(tile.uncertain ? 3 : 4)) }
    private var onlyOneSide: Bool { tile.uncertain && tile.alternatives.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(onlyOneSide ? "第 \(index + 1) 张可能是多认的，照片里有这张吗？" : "第 \(index + 1) 张看不太清，是哪个？")
                .font(.system(size: 16, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(candidates, id: \.self) { tile in
                    option(title: onlyOneSide ? "有这张" : tile.displayName, wins: hint(for: tile)) {
                        TileFace(tile: tile, width: 30)
                    } action: {
                        flow.choose(tile, at: index)
                    }
                }
                if tile.uncertain {
                    option(title: "没有这张", wins: removalHint) {
                        RoundedRectangle(cornerRadius: 30 * 0.16, style: .continuous)
                            .strokeBorder(Theme.faint, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(width: 30, height: 40)
                            .overlay(Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Theme.gray))
                    } action: {
                        flow.remove(at: index)
                    }
                }
            }
            .padding(.top, 14)
            Button("都不是，自己选 ›", action: other)
                .buttonStyle(.text(size: 14))
                .padding(.top, 4)
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
        .block()
    }

    private func option(title: String, wins: Bool?, @ViewBuilder face: () -> some View,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                face()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .medium))
                    if let wins {
                        Text(wins ? "选这个能和" : "选这个和不了")
                            .font(.system(size: 13))
                            .foregroundStyle(wins ? Theme.vermilion : Theme.gray)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .background(Color(hex: 0xFBFAF7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 只有这一张拿不准时，直接试一下能不能和；好几张都拿不准时，用规则引擎推荐的那组读法。
    private func hint(for tile: Tile) -> Bool? {
        if flow.pendingReviewCount == 1 { return flow.wins(with: tile, at: index) }
        if flow.recommendedRemovals.contains(index) { return false }
        guard let recommended = flow.recommended[index] else { return nil }
        return recommended == tile
    }

    private var removalHint: Bool? {
        if flow.pendingReviewCount == 1 { return flow.wins(removing: index) }
        if flow.recommendedRemovals.contains(index) { return true }
        return flow.recommended[index] == nil ? nil : false
    }
}

/// 全屏看拍的照片：双指放大、拖动，双击放大或复原。
private struct PhotoViewer: View {
    var photo: UIImage
    var close: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = min(5, max(1, lastScale * $0.magnification)) }
                        .onEnded { _ in
                            lastScale = scale
                            if scale == 1 { resetOffset() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = scale > 1 ? 1 : 2.5
                        lastScale = scale
                        if scale == 1 { resetOffset() }
                    }
                }
            Button("关闭", action: close)
                .buttonStyle(NavButtonStyle(color: .white))
                .padding(.horizontal, 20)
        }
        .statusBarHidden()
    }

    private func resetOffset() {
        offset = .zero
        lastOffset = .zero
    }
}
