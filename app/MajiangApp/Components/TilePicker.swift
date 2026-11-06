import SwiftUI
import MajiangKit

/// 34 种牌的选择面板：万、条、饼各一行，字牌一行。
struct TilePickerGrid: View {
    var selected: Tile?
    var onPick: (Tile) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 9)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([Suit.characters, .bamboo, .dots, .honors], id: \.self) { suit in
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Tile.all.filter { $0.suit == suit }, id: \.self) { tile in
                        Button {
                            onPick(tile)
                        } label: {
                            TileFace(tile: tile, width: 34)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Theme.ink, lineWidth: 2)
                                        .padding(-3)
                                        .opacity(tile == selected ? 1 : 0)
                                )
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// 选一张牌：换掉认错的牌，或者补一张漏掉的。
struct TileEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var current: Tile?
    var onPick: (Tile) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                TilePickerGrid(selected: current) { tile in
                    onPick(tile)
                    dismiss()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .page()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 加一组亮在桌上的牌（吃、碰、杠）。
struct MeldEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (Meld) -> Void

    enum Kind: String, CaseIterable, Identifiable {
        case chow = "吃", pung = "碰", kong = "明杠", concealedKong = "暗杠"
        var id: String { rawValue }
    }

    @State private var kind = Kind.pung

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SegmentedSwitch(options: Kind.allCases.map { ($0, $0.rawValue) }, selection: $kind)
                    Text(kind == .chow ? "选这组里最小的那张（567 饼就选 5 饼）" : "选是哪张牌")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.gray)
                    TilePickerGrid(selected: nil) { tile in
                        if let meld = makeMeld(tile) {
                            onAdd(meld)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .page()
            .navigationTitle("加一组亮在桌上的牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                NavClose { dismiss() }
            }
        }
    }

    private func makeMeld(_ tile: Tile) -> Meld? {
        switch kind {
        case .chow: return Meld.chow(tile)
        case .pung: return Meld.pung(tile)
        case .kong: return Meld.kong(tile, concealed: false)
        case .concealedKong: return Meld.kong(tile, concealed: true)
        }
    }
}
