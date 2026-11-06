import Foundation

/// 双读：端侧模型和 Gemini 同时跑。端侧几百毫秒就先给出结果（`preview`），Gemini 复核完再合并：
/// 两边读得一样的牌直接用；同一位置读得不一样的给两个候选让用户选；只有一边读到的标出来问一句。
/// 研究里的模拟（33 张）：两边完全一致的照片全部是对的，不一致的平均要点 2 下。
public struct DualReadRecognizer: ProgressiveTileRecognizer {
    public let name = "双读"
    /// 快的一路（端侧），先给结果。
    public var primary: TileRecognizer
    /// 慢但看得懂吃碰杠的一路（Gemini），合并时牌序和副露以它为准。
    public var secondary: TileRecognizer

    public init(primary: TileRecognizer, secondary: TileRecognizer) {
        self.primary = primary
        self.secondary = secondary
    }

    public func recognize(_ request: RecognitionRequest) async throws -> Recognition {
        try await recognize(request, preview: { _ in })
    }

    public func recognize(_ request: RecognitionRequest,
                          preview: @escaping @Sendable (Recognition) async -> Void) async throws -> Recognition {
        let secondary = secondary
        async let slow = Result(catching: { try await secondary.recognize(request) })
        let fast = await Result(catching: { try await primary.recognize(request) })
        if case .success(let quick) = fast { await preview(quick) }
        switch (fast, await slow) {
        case (.success(let a), .success(let b)):
            return Self.merge(b, with: a)
        case (.success(var a), .failure(let error)):
            // 说明会显示给用户：不提 Gemini、端侧，只说第一遍、第二遍
            a.notes.append("第二遍没复核上（\(Self.describe(error))），只有第一遍的读法，对照照片看一眼")
            return a
        case (.failure, .success(let b)):
            return b
        case (.failure, .failure(let error)):
            throw error
        }
    }

    private static func describe(_ error: Error) -> String {
        (error as? RecognitionError)?.message ?? error.localizedDescription
    }

    // MARK: 合并

    /// 合并两路结果。`base`（Gemini）的牌序和副露为准，`other`（端侧）的牌按顺序对齐上去：
    /// - 对上了、读法一样的不用看；
    /// - 对上了但读法不一样的，两种读法都是候选；
    /// - 只有 base 读到的标成待确认（可能是 base 多读了）；
    /// - 只有 other 读到、又不是副露里的牌，插在对应位置、标成待确认（可能是 base 漏读了）；
    ///   和明着的吃碰杠里的牌只差一点的，记一条说明（副露没法逐张给候选）。
    public static func merge(_ base: Recognition, with other: Recognition) -> Recognition {
        var merged = base
        merged.source = "双读"
        merged.notes = base.notes + other.notes.filter { !base.notes.contains($0) }

        let b = base.concealed.map(\.tile)
        let a = other.concealed.map(\.tile) + other.melds.flatMap(\.tiles)
        var meldPool = base.melds.flatMap(\.tiles)
        let steps = align(b, a, cheapToSkip: Set(meldPool))

        // 先把对得上副露的牌消掉，剩下的才是 other 多读到的
        var extras: [Int: Tile] = [:]  // steps 里的下标 → 牌
        for (k, step) in steps.enumerated() {
            guard case .otherOnly(let j) = step else { continue }
            if let index = meldPool.firstIndex(of: a[j]) { meldPool.remove(at: index) } else { extras[k] = a[j] }
        }
        // 明着的副露里没对上的牌，和多读到的牌挨得近，多半是副露里那张两边读得不一样
        var unmatchedMelds = base.melds.filter { !($0.kind == .kong && $0.isConcealed) }
            .filter { meld in meld.tiles.contains { meldPool.contains($0) } }
        for k in extras.keys.sorted() {
            let tile = extras[k]!
            guard let m = unmatchedMelds.firstIndex(where: { meld in
                meld.tiles.contains { $0.suit == tile.suit && ($0.isHonor || abs($0.rank - tile.rank) <= 3) && meldPool.contains($0) }
            }) else { continue }
            merged.notes.append("亮在桌上的「\(unmatchedMelds[m].displayText)」，另一遍读到的是 \(tile.displayName)，看一眼对不对")
            unmatchedMelds.remove(at: m)
            extras[k] = nil
        }

        var concealed: [RecognizedTile] = []
        for (k, step) in steps.enumerated() {
            switch step {
            case .both(let i, let j):
                var tile = base.concealed[i]
                if a[j] != tile.tile { tile.alternatives = Array(Set(tile.alternatives + [a[j]])).sorted() }
                concealed.append(tile)
            case .baseOnly(let i):
                var tile = base.concealed[i]
                tile.uncertain = true
                concealed.append(tile)
            case .otherOnly:
                if let tile = extras[k] { concealed.append(RecognizedTile(tile: tile, uncertain: true)) }
            }
        }
        merged.concealed = concealed

        if base.flowerCount != other.flowerCount {
            merged.flowerCount = max(base.flowerCount, other.flowerCount)
            merged.notes.append("宝牌两遍数得不一样（一遍 \(base.flowerCount) 张，一遍 \(other.flowerCount) 张），在下面改")
        }
        return merged
    }

    enum Step: Hashable {
        case both(Int, Int)
        case baseOnly(Int)
        case otherOnly(Int)
    }

    /// 两串牌按顺序对齐（编辑距离）。读法不同的代价：同花色 0.8 起、点数差越多越贵，不同花色 1.5；
    /// 跳过一张 1（`cheapToSkip` 里的牌只要 0.35，它们多半是 other 读进来的吃碰杠）。
    static func align(_ b: [Tile], _ a: [Tile], cheapToSkip: Set<Tile>) -> [Step] {
        func substitution(_ x: Tile, _ y: Tile) -> Double {
            if x == y { return 0 }
            if x.suit == y.suit { return x.isHonor ? 1 : 0.8 + 0.05 * Double(abs(x.rank - y.rank)) }
            return 1.5
        }
        func skipOther(_ y: Tile) -> Double { cheapToSkip.contains(y) ? 0.35 : 1 }

        let n = b.count, m = a.count
        var cost = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: 1, through: n, by: 1) { cost[i][0] = cost[i - 1][0] + 1 }
        for j in stride(from: 1, through: m, by: 1) { cost[0][j] = cost[0][j - 1] + skipOther(a[j - 1]) }
        for i in stride(from: 1, through: n, by: 1) {
            for j in stride(from: 1, through: m, by: 1) {
                cost[i][j] = min(cost[i - 1][j - 1] + substitution(b[i - 1], a[j - 1]),
                                 cost[i - 1][j] + 1,
                                 cost[i][j - 1] + skipOther(a[j - 1]))
            }
        }

        var steps: [Step] = []
        var i = n, j = m
        let epsilon = 1e-9
        while i > 0 || j > 0 {
            if i > 0, j > 0, abs(cost[i][j] - (cost[i - 1][j - 1] + substitution(b[i - 1], a[j - 1]))) < epsilon {
                steps.append(.both(i - 1, j - 1)); i -= 1; j -= 1
            } else if i > 0, abs(cost[i][j] - (cost[i - 1][j] + 1)) < epsilon {
                steps.append(.baseOnly(i - 1)); i -= 1
            } else {
                steps.append(.otherOnly(j - 1)); j -= 1
            }
        }
        return steps.reversed()
    }
}

/// 规则校验：识别结果凑不成和牌时，带着原因让同一路识别再看一次（研究里这一步把判胡从 31/33 提到 33/33）。
public struct RuleCheckedRecognizer: TileRecognizer {
    public var base: TileRecognizer
    public var name: String { base.name }

    public init(base: TileRecognizer) {
        self.base = base
    }

    public func recognize(_ request: RecognitionRequest) async throws -> Recognition {
        let first = try await base.recognize(request)
        guard let feedback = Self.problem(with: first) else { return first }
        var retry = request
        retry.previous = first
        retry.feedback = feedback
        guard let second = try? await base.recognize(retry) else { return first }
        return Self.problem(with: second) == nil ? second : first
    }

    /// 读出的牌有明显问题时返回原因。
    public static func problem(with recognition: Recognition) -> String? {
        let hand = recognition.hand
        if !hand.overusedTiles.isEmpty {
            return "你读出的牌里 \(hand.overusedTiles.map(\.notation).joined(separator: " ")) 超过 4 张，这不可能。"
        }
        if !FanCalculator.isWinningShape(hand) {
            let count = hand.allTiles.count
            return "按立直麻将规则，你读出的这 \(count) 张牌拼不成和牌。请对照照片逐张再核对一遍（常见的错是条子、饼子的点数差一，或漏读了被遮挡、切边的牌）。如果照片里的牌确实就是这样，就照实输出，不要为了凑成和牌而改。"
        }
        return nil
    }
}

/// 在两路读法不一致的牌里，找出能和的组合，标成推荐（确认页上的「选这个能和」）。
/// 只有一边读到的牌，「没有这张」也算一种读法。
/// 只有恰好一种组合能起和时才推荐；几种都能和时不替用户挑（挑番大的会偏向多算番），让用户对照照片选。
public enum RecognitionResolver {
    public struct Resolution: Hashable, Sendable {
        /// 每张需要确认的牌推荐的读法（下标同 `Recognition.concealed`）。
        public let recommended: [Int: Tile]
        /// 推荐删掉的牌（只有一边读到，删了才能和）。
        public let removals: Set<Int>
        public let result: ScoringResult?
    }

    public static func resolve(_ recognition: Recognition, context: WinContext,
                               minimumFan: Int = 1, maxFlagged: Int = 6) -> Resolution {
        let flagged = recognition.concealed.indices.filter { recognition.concealed[$0].needsReview }
        guard !flagged.isEmpty, flagged.count <= maxFlagged else {
            return Resolution(recommended: [:], removals: [],
                              result: try? FanCalculator.score(recognition.hand, context: context).get())
        }

        var winners: [(choice: [Int: Tile?], result: ScoringResult)] = []
        func search(_ k: Int, _ choice: [Int: Tile?]) {
            if k == flagged.count {
                let tiles = recognition.concealed.indices.compactMap { i -> Tile? in
                    if let chosen = choice[i] { return chosen }  // 选了「没有这张」时是 nil
                    return recognition.concealed[i].tile
                }
                let hand = Hand(melds: recognition.melds, concealed: tiles, winningTile: tiles.last)
                if case .success(let result) = FanCalculator.score(hand, context: context), result.meetsMinimum(minimumFan) {
                    winners.append((choice, result))
                }
                return
            }
            let index = flagged[k]
            let tile = recognition.concealed[index]
            let options: [Tile?] = tile.candidates.map { $0 } + (tile.uncertain ? [nil] : [])
            for option in options {
                var next = choice
                next[index] = .some(option)
                search(k + 1, next)
            }
        }
        search(0, [:])
        guard winners.count == 1, let only = winners.first else {
            return Resolution(recommended: [:], removals: [], result: nil)
        }
        return Resolution(recommended: only.choice.compactMapValues { $0 },
                          removals: Set(only.choice.filter { $0.value == nil }.keys),
                          result: only.result)
    }
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
