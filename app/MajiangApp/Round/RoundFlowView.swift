import SwiftUI
import MajiangKit

/// 记一局（14张胡牌拍照）或查大叫（13张流局拍照）：全屏弹出，拍照 → 核对 → 结果。
struct RoundFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var flow: RoundFlow
    @State private var lightBars = false
    var onFinish: (HandOutcome, UIImage?) -> Void
    var onFinishTingCheck: ((PlayerTingState) -> Void)?

    init(
        game: Game,
        mode: RoundFlow.Mode = .win,
        demo: DemoScreen? = nil,
        onFinish: @escaping (HandOutcome, UIImage?) -> Void,
        onFinishTingCheck: ((PlayerTingState) -> Void)? = nil
    ) {
        let flow = RoundFlow(game: game, mode: mode)
        #if DEBUG
        if let demo { DemoData.prepare(flow, for: demo) }
        #endif
        _flow = State(initialValue: flow)
        _lightBars = State(initialValue: !flow.steps.isEmpty)
        self.onFinish = onFinish
        self.onFinishTingCheck = onFinishTingCheck
    }

    private var checking: Bool { !flow.steps.isEmpty }

    var body: some View {
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
                    CheckView(flow: flow, finish: finish, finishTing: finishTing)
                }
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .background((checking ? Color.black : Theme.darkroom).ignoresSafeArea())
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: checking)
        .tint(Theme.ink)
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

    private func finishTing(_ state: PlayerTingState) {
        onFinishTingCheck?(state)
        dismiss()
    }
}
