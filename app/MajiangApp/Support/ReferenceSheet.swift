import SwiftUI
import MajiangKit

/// 给 Gemini 的牌面参考图。研究里用的参考图没有许可证，不能打包，所以用 App 自己画的扁平牌面现场生成。
/// 这张图对准确率的影响还没测过，需要用真实照片再跑一次对比。
enum ReferenceSheet {
    @MainActor
    static func jpegData() -> Data? {
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        return renderer.uiImage?.jpegData(compressionQuality: 0.85)
    }

    @MainActor
    private static var sheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([Suit.characters, .bamboo, .dots, .honors], id: \.self) { suit in
                HStack(spacing: 6) {
                    ForEach(Tile.all.filter { $0.suit == suit }, id: \.self) { tile in
                        VStack(spacing: 2) {
                            TileFace(tile: tile, width: 40)
                            Text(tile.notation).font(.system(size: 11, weight: .medium)).foregroundStyle(.black)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white)
    }
}
