import SwiftUI
import MajiangKit

/// 牌的显示状态：拿不准的牌用朱红虚线加「?」，认错的只有虚线，取景器里的示意牌发灰。
enum TileState {
    case normal, doubt, wrong, dim
}

/// 扁平真牌：饼画圆环，条画竹节，万写数字配红色「萬」，没有立体厚度。
/// 用在要对照桌上真牌的地方：核对页、候选、不成和提示。
struct TileFace: View {
    var tile: Tile
    var width: CGFloat = 44
    var state: TileState = .normal

    private var height: CGFloat { (width * 1.32).rounded() }
    private var inset: CGFloat { width * 0.14 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: width * 0.16, style: .continuous) }

    var body: some View {
        ZStack {
            shape
                .fill(Theme.tileShadow)
                .offset(y: 1.5)
            shape
                .fill(state == .dim ? Theme.tileDim : Theme.tileFace)
            shape
                .strokeBorder(Theme.tileEdge, lineWidth: 1)
            face
                .frame(width: width - 2 * inset, height: height - 2 * inset)
        }
        .frame(width: width, height: height)
        .opacity(state == .dim ? 0.9 : 1)
        .overlay {
            if state == .doubt || state == .wrong {
                RoundedRectangle(cornerRadius: width * 0.16 + 3, style: .continuous)
                    .strokeBorder(Theme.vermilion, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .padding(-4.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if state == .doubt {
                Text("?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Theme.vermilion, in: Circle())
                    .offset(x: 7, y: -7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(tile.displayName + (state == .doubt ? "，拿不准" : ""))
    }

    @ViewBuilder
    private var face: some View {
        switch tile.suit {
        case .dots: DotsFace(rank: tile.rank)
        case .bamboo: BambooFace(rank: tile.rank)
        case .characters: CharacterFace(rank: tile.rank, width: width)
        case .honors: HonorFace(tile: tile, width: width)
        }
    }
}

/// 图案里的一个点，单位坐标（0–1）。
private struct Spot {
    var x: CGFloat
    var y: CGFloat
    var red = false
}

private func spot(_ x: CGFloat, _ y: CGFloat, red: Bool = false) -> Spot { Spot(x: x, y: y, red: red) }

/// 网格排列；`red` 决定哪些点画成红色。
private func grid(_ xs: [CGFloat], _ ys: [CGFloat], red: (CGFloat, CGFloat) -> Bool = { _, _ in false }) -> [Spot] {
    var spots: [Spot] = []
    for y in ys {
        for x in xs { spots.append(Spot(x: x, y: y, red: red(x, y))) }
    }
    return spots
}

/// 在单位坐标里摆放图案。
private struct Pattern<Content: View>: View {
    var points: [Spot]
    var mark: (Bool) -> Content

    var body: some View {
        GeometryReader { geo in
            ForEach(points.indices, id: \.self) { i in
                mark(points[i].red)
                    .position(x: points[i].x * geo.size.width, y: points[i].y * geo.size.height)
            }
        }
    }
}

/// 饼：圆环加实心圆点，蓝、绿、红三色，排法和设计稿一致。
private struct DotsFace: View {
    var rank: Int

    private struct Dot {
        var x: CGFloat
        var y: CGFloat
        var color: Color
        /// 直径占牌面内宽的比例。
        var size: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ForEach(Array(Self.layout(rank).enumerated()), id: \.offset) { _, dot in
                let s = dot.size * w
                ZStack {
                    Circle().strokeBorder(dot.color, lineWidth: max(1, s * 0.13))
                    Circle().fill(dot.color).frame(width: s * 0.34, height: s * 0.34)
                }
                .frame(width: s, height: s)
                .position(x: dot.x * w, y: dot.y * geo.size.height)
            }
        }
    }

    private static func layout(_ rank: Int) -> [Dot] {
        let b = Theme.tileBlue, g = Theme.tileGreen, r = Theme.tileRed
        let spec: [(CGFloat, CGFloat, Color, CGFloat)]
        switch rank {
        case 1: spec = [(0.5, 0.5, r, 0.86)]
        case 2: spec = [(0.5, 0.26, g, 0.46), (0.5, 0.74, b, 0.46)]
        case 3: spec = [(0.2, 0.16, b, 0.38), (0.5, 0.5, r, 0.38), (0.8, 0.84, g, 0.38)]
        case 4: spec = [(0.26, 0.27, b, 0.44), (0.74, 0.27, g, 0.44), (0.26, 0.73, g, 0.44), (0.74, 0.73, b, 0.44)]
        case 5: spec = [(0.22, 0.2, b, 0.38), (0.78, 0.2, g, 0.38), (0.5, 0.5, r, 0.38), (0.22, 0.8, g, 0.38), (0.78, 0.8, b, 0.38)]
        case 6: spec = [(0.27, 0.16, g, 0.38), (0.73, 0.16, g, 0.38), (0.27, 0.5, r, 0.38), (0.73, 0.5, r, 0.38),
                        (0.27, 0.84, r, 0.38), (0.73, 0.84, r, 0.38)]
        case 7: spec = [(0.18, 0.1, g, 0.3), (0.5, 0.23, g, 0.3), (0.82, 0.36, g, 0.3), (0.27, 0.63, r, 0.34),
                        (0.73, 0.63, r, 0.34), (0.27, 0.89, r, 0.34), (0.73, 0.89, r, 0.34)]
        case 8:
            var dots: [(CGFloat, CGFloat, Color, CGFloat)] = []
            for y: CGFloat in [0.11, 0.37, 0.63, 0.89] {
                dots.append((0.27, y, b, 0.32))
                dots.append((0.73, y, b, 0.32))
            }
            spec = dots
        default:
            var dots: [(CGFloat, CGFloat, Color, CGFloat)] = []
            for (y, c) in [(CGFloat(0.16), b), (0.5, r), (0.84, g)] {
                for x: CGFloat in [0.17, 0.5, 0.83] { dots.append((x, y, c, 0.3)) }
            }
            spec = dots
        }
        return spec.map { Dot(x: $0.0, y: $0.1, color: $0.2, size: $0.3) }
    }
}

private struct BambooFace: View {
    var rank: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * (rank == 8 ? 0.13 : 0.15)
            let h = geo.size.height * (rank >= 7 ? 0.26 : 0.36)
            if rank == 1 {
                // 幺鸡：画成一根带红顶的大竹节，和桌上的鸟一眼对得上
                VStack(spacing: geo.size.height * 0.04) {
                    Circle().fill(Theme.tileRed).frame(width: geo.size.width * 0.3)
                    Stick(red: false).frame(width: geo.size.width * 0.22, height: geo.size.height * 0.62)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            } else {
                Pattern(points: Self.layout(rank)) { red in
                    Stick(red: red).frame(width: w, height: h)
                }
            }
        }
    }

    static func layout(_ rank: Int) -> [Spot] {
        switch rank {
        case 2: return [spot(0.5, 0.27), spot(0.5, 0.73)]
        case 3: return [spot(0.5, 0.27), spot(0.28, 0.73), spot(0.72, 0.73)]
        case 4: return grid([0.28, 0.72], [0.27, 0.73])
        case 5: return grid([0.2, 0.8], [0.27, 0.73]) + [spot(0.5, 0.5, red: true)]
        case 6: return grid([0.2, 0.5, 0.8], [0.27, 0.73])
        case 7: return [spot(0.5, 0.15, red: true)] + grid([0.2, 0.5, 0.8], [0.5, 0.84])
        case 8: return grid([0.14, 0.38, 0.62, 0.86], [0.27, 0.73])
        default: return grid([0.2, 0.5, 0.8], [0.15, 0.5, 0.85], red: { x, _ in x == 0.5 })
        }
    }
}

/// 一节竹子：圆角竖条，中间一道节。
private struct Stick: View {
    var red: Bool

    var body: some View {
        GeometryReader { geo in
            let color = red ? Theme.tileRed : Theme.tileGreen
            ZStack {
                Capsule().fill(color)
                Rectangle().fill(Theme.tileFace).frame(height: max(1, geo.size.height * 0.07))
            }
        }
    }
}

private struct CharacterFace: View {
    var rank: Int
    var width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(Tile(suit: .characters, rank: rank)!.faceCharacter)
                .font(.system(size: width * 0.42, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("萬")
                .font(.system(size: width * 0.44, weight: .bold))
                .foregroundStyle(Theme.tileRed)
        }
        .minimumScaleFactor(0.5)
    }
}

private struct HonorFace: View {
    var tile: Tile
    var width: CGFloat

    var body: some View {
        if tile.rank == 7 {
            // 白板：蓝色细框
            RoundedRectangle(cornerRadius: width * 0.08)
                .stroke(Theme.tileBlue, lineWidth: max(1.5, width * 0.05))
                .padding(width * 0.06)
        } else {
            Text(tile.faceCharacter)
                .font(.system(size: width * 0.62, weight: .heavy))
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
        }
    }

    private var color: Color {
        switch tile.rank {
        case 5: Theme.tileRed
        case 6: Theme.tileGreen
        default: Theme.ink
        }
    }
}

/// 一排扁平真牌。
struct TileRow: View {
    var tiles: [Tile]
    var width: CGFloat = 36

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                TileFace(tile: tile, width: width)
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([Suit.characters, .bamboo, .dots, .honors], id: \.self) { suit in
                TileRow(tiles: Tile.all.filter { $0.suit == suit }, width: 36)
            }
        }
        .padding()
    }
    .page()
}
