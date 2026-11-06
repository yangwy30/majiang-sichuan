import SwiftUI
import UniformTypeIdentifiers
import MajiangKit

/// 备份与换手机：iCloud 同步开关，加上不用 iCloud 时的导出 / 导入文件。
struct BackupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        @Bindable var cloud = model.cloud
        NavigationStack {
            Form {
                Section {
                    Toggle("iCloud 同步", isOn: $cloud.enabled)
                        .onChange(of: cloud.enabled) { _, on in
                            if on { Task { await model.syncNow() } }
                        }
                    if let line = statusLine {
                        Text(line)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.gray)
                    }
                } footer: {
                    Text("牌局存在你自己的 iCloud 里，别人看不到。换新手机时登录同一个 Apple ID，打开 App 记录就都回来了；iPad 上装了也会同步。")
                }

                Section {
                    Button("导出全部牌局") { export() }
                    Button("从文件导入") { importing = true }
                } header: {
                    Text("不用 iCloud")
                } footer: {
                    Text("导出一个文件，存到「文件」或隔空投送到新手机，在新手机上点「从文件导入」。导入只会添加和更新，不会删掉这台手机上已有的牌局。")
                }
            }
            .page()
            .navigationTitle("备份与换手机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose("关闭") { dismiss() }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): importFile(url)
                case .failure(let error): message = "没有导入：\(error.localizedDescription)"
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("好") { message = nil }
            }
        }
    }

    private var statusLine: String? {
        switch model.cloud.status {
        case .off: nil
        case .unavailable(let reason), .failed(let reason): reason
        case .syncing: "正在同步…"
        case .synced(let date): "已同步 · \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    private func export() {
        do {
            ShareSheet.present([try model.exportFile()])
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importFile(_ url: URL) {
        do {
            let summary = try model.importFile(url)
            message = summary.isEmpty ? "文件里的牌局这台手机上都有了。"
                : [summary.added > 0 ? "加了 \(summary.added) 场牌局" : nil,
                   summary.updated > 0 ? "更新了 \(summary.updated) 场" : nil]
                    .compactMap { $0 }.joined(separator: "，") + "。"
        } catch {
            message = "这个文件读不出来，确认是「导出全部牌局」导出的文件。"
        }
    }
}
