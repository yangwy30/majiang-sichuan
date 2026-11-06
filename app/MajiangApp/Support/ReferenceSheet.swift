import SwiftUI
import MajiangKit

/// 给 Gemini 的川麻 27 种序数牌牌面参考图（仅万、条、筒，无字牌与花牌）。
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
            ForEach(Suit.sichuan, id: \.self) { suit in
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
