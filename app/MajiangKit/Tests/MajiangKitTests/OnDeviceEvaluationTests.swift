#if canImport(CoreML) && canImport(ImageIO)
import XCTest
@testable import MajiangKit

/// 在 Mac 上用测试照片评测端侧认牌和双读（走 App 里同一套代码）。没设环境变量时跳过，CI 和 Linux 不跑。
///
///     MAJIANG_TILE_MODEL=~/…/MahjongTileDetector.mlpackage   端侧模型（不进仓库，见 app/README.md）
///     MAJIANG_PHOTOS=~/Downloads/majiang-test-photos          照片目录（默认就是这个）
///     MAJIANG_GEMINI_KEY_FILE=~/.config/gemini/api_key        可选：给了就同时跑 Gemini，评测双读
///     MAJIANG_REF_SHEET=…/reference_tiles.jpg                 可选：给 Gemini 的牌面参考图
///     MAJIANG_EVAL_OUT=out.json                               可选：逐张结果写到这里
///     swift test --filter OnDeviceEvaluationTests
final class OnDeviceEvaluationTests: XCTestCase {
    private struct GroundTruth: Decodable {
        struct Photo: Decodable {
            var id: String
            var file: String
            var tiles: String
            var win: Bool?
        }
        var photos: [Photo]
    }

    private struct KeyFile: APIKeyProvider {
        var url: URL
        func apiKey() throws -> String {
            try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private struct Row: Encodable {
        var id: String
        var truth: String
        var onDevice: String
        var onDeviceExact: Bool
        var onDeviceWin: Bool
        var truthWin: Bool?
        var ms: Int
        var notes: [String]
        var gemini: String?
        var geminiExact: Bool?
        var merged: String?
        /// 双读后要用户确认的牌数；0 表示自动通过。
        var review: Int?
        /// 自动通过而且全对。
        var autoCorrect: Bool?
        /// 要确认时，用户在候选里选得出正确答案。
        var reachable: Bool?
        /// 规则引擎推荐的那组读法正好是对的。
        var resolverRight: Bool?
    }

    private static func env(_ name: String) -> String? {
        ProcessInfo.processInfo.environment[name].map { NSString(string: $0).expandingTildeInPath }
    }

    private static func sorted(_ tiles: [Tile]) -> String { tiles.sorted().map(\.notation).joined(separator: " ") }

    func testOnDeviceAndDualReadOnTestPhotos() async throws {
        guard let modelPath = Self.env("MAJIANG_TILE_MODEL") else {
            throw XCTSkip("没设 MAJIANG_TILE_MODEL，跳过端侧评测")
        }
        let photos = URL(fileURLWithPath: Self.env("MAJIANG_PHOTOS") ?? NSString(string: "~/Downloads/majiang-test-photos").expandingTildeInPath)
        let truthURL = try XCTUnwrap(Bundle.module.url(forResource: "ground_truth", withExtension: "json", subdirectory: "Fixtures"))
        let truth = try JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: truthURL))

        let modelURL = URL(fileURLWithPath: modelPath)
        let compiled = modelURL.pathExtension == "mlmodelc" ? modelURL : try await CoreMLTileDetector.compileModel(at: modelURL)
        let onDevice = OnDeviceRecognizer(detector: try CoreMLTileDetector(compiledModelAt: compiled))

        var gemini: TileRecognizer?
        if let keyPath = Self.env("MAJIANG_GEMINI_KEY_FILE") {
            let sheet = try Self.env("MAJIANG_REF_SHEET").map { (data: try Data(contentsOf: URL(fileURLWithPath: $0)), mimeType: "image/jpeg") }
            let config = GeminiConfiguration(endpoint: .direct(KeyFile(url: URL(fileURLWithPath: keyPath))), referenceSheet: sheet)
            gemini = RuleCheckedRecognizer(base: GeminiRecognizer(configuration: config))
        }

        var rows: [Row] = []
        for photo in truth.photos {
            let url = photos.appendingPathComponent(photo.file)
            guard let data = try? Data(contentsOf: url) else {
                print("缺照片 \(url.path)")
                continue
            }
            let expected = Tile.parseList(photo.tiles)
            let request = RecognitionRequest(image: data, mimeType: url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg")

            let start = Date()
            let local = (try? await onDevice.recognize(request)) ?? Recognition(concealed: [RecognizedTile](), source: "端侧")
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            var row = Row(id: photo.id, truth: Self.sorted(expected), onDevice: local.concealed.map(\.tile.notation).joined(separator: " "),
                          onDeviceExact: Self.sorted(local.hand.allTiles) == Self.sorted(expected),
                          onDeviceWin: FanCalculator.isWinningShape(local.hand), truthWin: photo.win, ms: ms, notes: local.notes)

            if let gemini {
                do {
                    let remote = try await gemini.recognize(request)
                    row.gemini = Self.sorted(remote.hand.allTiles)
                    row.geminiExact = Self.sorted(remote.hand.allTiles) == Self.sorted(expected)
                    let merged = local.concealed.isEmpty ? remote : DualReadRecognizer.merge(remote, with: local)
                    row.merged = merged.concealed.map { $0.needsReview ? "[\($0.candidates.map(\.notation).joined(separator: "/"))\($0.uncertain ? "/无" : "")]" : $0.tile.notation }
                        .joined(separator: " ") + (merged.melds.isEmpty ? "" : " | " + merged.melds.map(\.displayText).joined(separator: " "))
                    row.notes += merged.notes.filter { !row.notes.contains($0) }
                    row.review = merged.reviewCount
                    row.autoCorrect = merged.reviewCount == 0 && Self.sorted(merged.hand.allTiles) == Self.sorted(expected)
                    row.reachable = Self.reachable(merged, expected: expected)
                    let resolution = RecognitionResolver.resolve(merged, context: WinContext(selfDrawn: true), minimumFan: 0)
                    if !resolution.recommended.isEmpty || !resolution.removals.isEmpty {
                        var tiles: [Tile] = []
                        for (i, t) in merged.concealed.enumerated() where !resolution.removals.contains(i) {
                            tiles.append(resolution.recommended[i] ?? t.tile)
                        }
                        row.resolverRight = Self.sorted(tiles + merged.melds.flatMap(\.tiles)) == Self.sorted(expected)
                    }
                } catch {
                    row.notes.append("Gemini 失败：\(error)")
                }
            }
            print(String(format: "%@ %@ %4d ms  端侧=%@", photo.id, row.onDeviceExact ? "✅" : "❌", ms, row.onDevice)
                  + (row.merged.map { "\n        双读=\($0)  review=\(row.review ?? 0)" } ?? ""))
            rows.append(row)
        }

        let n = rows.count
        let exact = rows.filter(\.onDeviceExact).count
        let winRows = rows.filter { $0.truthWin != nil }
        let winOK = winRows.filter { $0.onDeviceWin == $0.truthWin }.count
        let median = rows.map(\.ms).sorted()[n / 2]
        print("端侧：整手全对 \(exact)/\(n)，胡没胡判对 \(winOK)/\(winRows.count)，中位 \(median) ms")
        if gemini != nil {
            let auto = rows.filter { $0.review == 0 }
            let reviewed = rows.filter { ($0.review ?? 0) > 0 }
            print("Gemini 单独：整手全对 \(rows.filter { $0.geminiExact == true }.count)/\(n)")
            print("双读：自动通过 \(auto.count)/\(n)（其中全对 \(auto.filter { $0.autoCorrect == true }.count)），"
                  + "要确认 \(reviewed.count) 张照片、平均 \(String(format: "%.1f", Double(reviewed.compactMap(\.review).reduce(0, +)) / Double(max(1, reviewed.count)))) 张牌，"
                  + "候选里选得出正确答案 \(reviewed.filter { $0.reachable == true }.count)/\(reviewed.count)，"
                  + "规则引擎推荐对 \(rows.filter { $0.resolverRight == true }.count) / 推荐了 \(rows.filter { $0.resolverRight != nil }.count)")
        }
        if let out = Self.env("MAJIANG_EVAL_OUT") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(rows).write(to: URL(fileURLWithPath: out))
        }
        XCTAssertGreaterThan(exact, 0, "端侧一张都没认对，模型或预处理有问题")
    }

    /// 在每张待确认的牌的候选里（只有一边读到的还可以选「没有」）选得出正确答案吗。
    private static func reachable(_ merged: Recognition, expected: [Tile]) -> Bool {
        let flagged = merged.concealed.indices.filter { merged.concealed[$0].needsReview }
        guard flagged.count <= 10 else { return false }
        let target = sorted(expected)
        func search(_ k: Int, _ chosen: [Int: Tile?]) -> Bool {
            if k == flagged.count {
                let tiles = merged.concealed.indices.compactMap { i -> Tile? in
                    if let c = chosen[i] { return c }
                    return merged.concealed[i].tile
                }
                return sorted(tiles + merged.melds.flatMap(\.tiles)) == target
            }
            let tile = merged.concealed[flagged[k]]
            let options: [Tile?] = tile.candidates.map { $0 } + (tile.uncertain ? [nil] : [])
            return options.contains { option in
                var next = chosen
                next[flagged[k]] = .some(option)
                return search(k + 1, next)
            }
        }
        return search(0, [:])
    }
}
#endif
