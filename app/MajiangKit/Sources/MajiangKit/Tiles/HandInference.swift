import Foundation

extension Hand {
    /// 从一串不分组的牌推出一手牌：14 张全当立牌；多出 k 张时，把 k 组四张相同的牌当成杠。
    /// 照片看不出吃碰，所以推出来的副露只有杠，吃碰分组要让用户确认。和张取最后一张。
    public static func inferred(fromFlat tiles: [Tile], winningTile: Tile? = nil) -> Hand? {
        let extra = tiles.count - 14
        guard (0...4).contains(extra) else { return nil }
        if extra == 0 { return Hand(concealed: tiles, winningTile: winningTile) }

        let counts = Dictionary(grouping: tiles, by: { $0 }).mapValues(\.count)
        let quads = counts.filter { $0.value == 4 }.keys.sorted()
        guard quads.count >= extra else { return nil }

        // 和张不能整组被拿去当杠。
        let win = winningTile ?? tiles.last
        let kongTiles = Array((quads.filter { $0 != win } + quads.filter { $0 == win }).prefix(extra))
        var standing = tiles
        for tile in kongTiles {
            for _ in 0..<4 {
                if let i = standing.firstIndex(of: tile) { standing.remove(at: i) }
            }
        }
        return Hand(melds: kongTiles.map { .kong($0, concealed: false) }, concealed: standing, winningTile: win)
    }
}
