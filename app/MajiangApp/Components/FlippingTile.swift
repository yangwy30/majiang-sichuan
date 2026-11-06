import SwiftUI
import MajiangKit

/// 牌背：墨绿，和桌上的真牌一样，没有图案。
struct TileBack: View {
    var width: CGFloat = 44

    private var height: CGFloat { (width * 1.32).rounded() }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: width * 0.16, style: .continuous) }

    var body: some View {
        ZStack {
            shape
                .fill(Color(hex: 0x1F3D2F))
                .offset(y: 1.5)
            shape
                .fill(Theme.tileGreen)
            shape
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                .padding(width * 0.09)
        }
        .frame(width: width, height: height)
    }
}

/// 核对页「再认一遍」时的牌：一波一波翻到牌背再翻回来，从左往右挨个错开。
/// `active` 关掉就停在正面；系统开了「减弱动态效果」就不翻。
struct FlippingTile<Face: View>: View {
    var index: Int
    var width: CGFloat
    var active: Bool
    /// 从这个时刻开始翻（等牌落定以后）。
    var start: Date
    @ViewBuilder var face: Face

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 每隔多久翻一波、每张翻一下多久、相邻两张错开多久。
    static var period: TimeInterval { 2.4 }
    static var duration: TimeInterval { 0.6 }
    static var stagger: TimeInterval { 0.11 }

    var body: some View {
        if active && !reduceMotion {
            TimelineView(.animation) { context in
                let angle = Self.angle(at: context.date.timeIntervalSince(start), index: index)
                ZStack {
                    if angle > 90 && angle < 270 {
                        TileBack(width: width)
                    } else {
                        face
                    }
                }
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            }
        } else {
            face
        }
    }

    /// 第 `index` 张在 `t` 秒时转到多少度（0–360，翻正面→牌背→正面，两半各自缓入缓出）。
    static func angle(at t: TimeInterval, index: Int) -> Double {
        let local = t - Double(index) * stagger
        guard local > 0 else { return 0 }
        let phase = local.truncatingRemainder(dividingBy: period)
        guard phase < duration else { return 0 }
        let half = duration / 2
        let p = phase < half ? phase / half : (phase - half) / half
        let eased = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
        return (phase < half ? 0 : 180) + eased * 180
    }
}
