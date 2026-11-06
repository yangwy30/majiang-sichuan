import UIKit

/// 和牌时拍的那张照片。压缩后只存在这台手机上：不进 iCloud 同步，也不进导出文件。
/// 文件名就是那一局的编号（`HandRecord.id`），删局、撤销时跟着删。
enum HandPhotos {
    /// 长边压到 1600 像素，一张两三百 KB，一场 16 局也就几 MB。
    private static let maxSide: CGFloat = 1600

    static let directory: URL = {
        let url: URL
        if DemoScreen.current != nil {
            // 截图用的假照片放临时目录
            url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-photos", isDirectory: true)
        } else {
            url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("majiang", isDirectory: true)
                .appendingPathComponent("photos", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("jpg")
    }

    /// 压缩后写盘，放在后台做，不卡记账。
    static func save(_ image: UIImage, for id: UUID) {
        Task.detached(priority: .utility) {
            guard let data = compressed(image) else { return }
            try? data.write(to: url(for: id), options: .atomic)
        }
    }

    static func load(_ id: UUID) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url(for: id).path)
        }.value
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// 删掉账本里已经没有的那几局的照片（比如别的设备上删了局，同步过来）。
    static func prune(keeping ids: Set<UUID>) {
        Task.detached(priority: .background) {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "jpg" {
                let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
                if id.map({ !ids.contains($0) }) ?? true { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    static func compressed(_ image: UIImage) -> Data? {
        image.downscaled(maxSide: maxSide).jpegData(compressionQuality: 0.72)
    }
}
