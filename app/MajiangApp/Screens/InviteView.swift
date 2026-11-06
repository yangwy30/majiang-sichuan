import SwiftUI
import MajiangKit

/// AI 认牌的邀请码：填码开启，或者看已经填的码、移除。码对不对由中转站说了算。
/// 没码也能正常用：拍照后用离线认牌，读错的点一下改；也可以手动选牌。
/// 样子跟开局页一样：大标题、一块白，底部一个黑色主按钮，不能点时按钮上写原因。
struct InviteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var complete: Bool { InviteCode.normalize(input) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let code = model.inviteCode {
                        PageTitle(title: "AI 认牌已开启", subtitle: "拍照后 AI 再认一遍，两边读得不一样的牌让你选。")
                        CodeCells(text: code, cursor: nil)
                            .padding(.top, 36)
                    } else {
                        PageTitle(title: "填邀请码", subtitle: "开启 AI 认牌，用云端大模型读牌，更准。")
                        CodeCells(text: input, cursor: focused && !busy ? input.count : nil)
                            .overlay { field }
                            .contentShape(Rectangle())
                            .onTapGesture { focused = true }
                            .padding(.top, 36)

                        Text(error ?? model.inviteNotice ?? " ")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("没有邀请码？")
                                .font(.system(size: 15, weight: .medium))
                            Text("照样能用。拍照后用手机上的离线认牌，读错的牌点一下改，也可以手动选牌。算番、记账都一样。")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 28)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.never)
            .page()
            .bottomBar {
                if model.inviteCode != nil {
                    Button("好") { dismiss() }
                        .buttonStyle(.primary)
                    Button("移除邀请码") { model.removeInvite() }
                        .buttonStyle(.text(size: 14))
                } else {
                    Button(busy ? "正在确认…" : complete ? "开启" : "填好 6 位邀请码", action: redeem)
                        .buttonStyle(.primary)
                        .disabled(!complete || busy)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose("关闭") { dismiss() }
            }
            .onAppear {
                #if DEBUG
                if model.demoScreen == .invite && input.isEmpty { input = "K7MP" }
                #endif
                if model.inviteCode == nil { focused = true }
            }
        }
    }

    /// 看不见的输入框盖在六个格子上：格子负责好看，它负责键盘。只收码里会出现的字，自动转大写。
    private var field: some View {
        TextField("", text: $input)
            .focused($focused)
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(redeem)
            .foregroundStyle(.clear)
            .tint(.clear)
            .opacity(0.02)
            .disabled(busy)
            .onChange(of: input) { _, new in
                let cleaned = String(new.uppercased().filter(InviteCode.alphabet.contains).prefix(InviteCode.length))
                if cleaned != new { input = cleaned }
                error = nil
                // 填满 6 位直接去确认，不用再按按钮
                if cleaned == new && cleaned.count == InviteCode.length { redeem() }
            }
            .accessibilityLabel("邀请码")
    }

    private func redeem() {
        guard !busy, complete else { return }
        busy = true
        Task {
            error = await model.redeemInvite(input)
            busy = false
            if error == nil { input = "" }
        }
    }
}

/// 六个白格子，一格一个字；正在填的那格描一圈墨色。
private struct CodeCells: View {
    var text: String
    /// 光标在第几格；nil 表示不显示。
    var cursor: Int?

    var body: some View {
        let chars = Array(text)
        HStack(spacing: 8) {
            ForEach(0..<InviteCode.length, id: \.self) { i in
                Text(i < chars.count ? String(chars[i]) : " ")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Theme.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(cursor == i ? Theme.ink : Theme.line, lineWidth: cursor == i ? 1.5 : 1)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text.isEmpty ? "还没填" : text.map(String.init).joined(separator: " "))
    }
}
