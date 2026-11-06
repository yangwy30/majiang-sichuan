import SwiftUI
import MajiangKit

/// 记一局：全屏弹出，拍照 → 核对 → 结果。记下或关掉后回到牌桌。
struct RoundFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var flow: RoundFlow
    /// 状态栏跟着谁在最上面：核对页升到顶以后才换成深色字，不然升的半路上是黑底黑字。
    @State private var lightBars = false
    /// 记下的结果，和拍的那张照片（手动输入的没有）。
    var onFinish: (HandOutcome, UIImage?) -> Void

    init(game: Game, demo: DemoScreen? = nil, onFinish: @escaping (HandOutcome, UIImage?) -> Void) {
        let flow = RoundFlow(game: game)
        #if DEBUG
        if let demo { DemoData.prepare(flow, for: demo) }
        #endif
        _flow = State(initialValue: flow)
        _lightBars = State(initialValue: !flow.steps.isEmpty)
        self.onFinish = onFinish
    }

    private var checking: Bool { !flow.steps.isEmpty }

    var body: some View {
        // 核对页不是推进来的：拍照页往后退一点、变暗，核对页从下面升上来，牌一张张落进格子里
        ZStack {
            NavigationStack {
                CaptureView(flow: flow) { dismiss() }
            }
            .clipShape(RoundedRectangle(cornerRadius: checking ? 28 : 0, style: .continuous))
            .scaleEffect(checking ? 0.94 : 1, anchor: .top)
            .opacity(checking ? 0.45 : 1)
            .allowsHitTesting(!checking)

            if checking {
                NavigationStack {
                    CheckView(flow: flow, finish: finish)
                }
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        // 拍照页被圆角裁过，边上的安全区（iPhone Duo 外屏右边竖着的状态栏、底部横条）露的是这层底色：
        // 平时跟拍照页同色，免得有一道接缝；核对页升上来时才换成纯黑，衬出往后退的拍照页
        .background((checking ? Color.black : Theme.darkroom).ignoresSafeArea())
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: checking)
        .tint(Theme.ink)
        // 拍照页是深色底，状态栏要白字；导航栏的 toolbarColorScheme 管不到整个全屏弹层
        .preferredColorScheme(lightBars ? .light : .dark)
        .task(id: checking) {
            guard checking else {
                lightBars = false
                return
            }
            if lightBars { return }
            try? await Task.sleep(for: .seconds(0.45))
            if !Task.isCancelled { lightBars = true }
        }
    }

    private func finish(_ outcome: HandOutcome) {
        flow.showResult = false
        onFinish(outcome, flow.photo)
        dismiss()
    }
}
