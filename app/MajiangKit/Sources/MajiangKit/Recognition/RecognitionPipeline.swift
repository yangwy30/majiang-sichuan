import Foundation

/// 双读：端侧模型和 Gemini 同时跑。端侧几百毫秒就先给出结果（`preview`），Gemini 复核完再合并：
/// 两边读得一样的牌直接用；同一位置读得不一样的给两个候选让用户选；只有一边读到的标出来问一句。
public struct DualReadRecognizer: ProgressiveTileRecognizer {
    public let name = "双读"
    /// 快的一路（端侧），先给结果。
    public var primary: TileRecognizer
    /// 慢但看得懂碰杠的一路（Gemini），合并时牌序和副露以它为准。
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

    public static func merge(_ base: Recognition, with other: Recognition) -> Recognition {
        var merged = base
        merged.source = "双读"
        merged.notes = base.notes + other.notes.filter { !base.notes.contains($0) }

        let b = base.concealed.map(\.tile)
        let a = other.concealed.map(\.tile) + other.melds.flatMap(\.tiles)
        var meldPool = base.melds.flatMap(\.tiles)
        let steps = align(b, a, cheapToSkip: Set(meldPool))

        var extras: [Int: Tile] = [:]
        for (k, step) in steps.enumerated() {
            guard case .otherOnly(let j) = step else { continue }
            if let index = meldPool.firstIndex(of: a[j]) { meldPool.remove(at: index) } else { extras[k] = a[j] }
        }
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
        merged.flowerCount = 0
        return merged
    }

    enum Step: Hashable {
        case both(Int, Int)
        case baseOnly(Int)
        case otherOnly(Int)
    }

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

/// 规则校验：识别结果凑不成胡牌（且不是 13 张流局查叫手牌）时，带着原因让同一路识别再看一次。
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
        // 如果是 13 张（查大叫手牌），只要没有超过 4 张即可，不要求凑成 14 张胡牌
        if hand.hasValidTenpaiTileCount {
            return nil
        }
        if !FanCalculator.isWinningShape(hand) {
            let count = hand.allTiles.count
            return "按四川麻将规则（需缺一门），你读出的这 \(count) 张牌拼不成胡牌。请对照照片逐张再核对一遍（常见的错是条子、筒子的点数差一，或漏读了被遮挡、切边的牌）。如果照片里的牌确实就是这样（例如流局查叫的 13 张牌），就照实输出，不要为了凑成胡牌而改。"
        }
        return nil
    }
}

public typealias RecognitionResolution = RecognitionResolver.Resolution

/// 在两路读法不一致的牌里，找出能胡的组合，标成推荐（确认页上的「选这个能胡」）。
public enum RecognitionResolver {
    public struct Resolution: Hashable, Sendable {
        public let recommended: [Int: Tile]
        public let removals: Set<Int>
        public let result: ScoringResult?

        public var hasRecommendations: Bool {
            !recommended.isEmpty || !removals.isEmpty
        }
    }

    public static func resolve(_ recognition: Recognition, context: WinContext,
                               minimumFan: Int = 0, maxFlagged: Int = 6) -> Resolution {
        let flagged = recognition.concealed.indices.filter { recognition.concealed[$0].needsReview }
        guard !flagged.isEmpty, flagged.count <= maxFlagged else {
            return Resolution(recommended: [:], removals: [],
                              result: try? FanCalculator.score(recognition.hand, context: context).get())
        }

        var winners: [(choice: [Int: Tile?], result: ScoringResult)] = []
        func search(_ k: Int, _ choice: [Int: Tile?]) {
            if k == flagged.count {
                let tiles = recognition.concealed.indices.compactMap { i -> Tile? in
                    if let chosen = choice[i] { return chosen }
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
