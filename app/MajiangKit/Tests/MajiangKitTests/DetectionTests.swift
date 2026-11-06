import XCTest
@testable import MajiangKit

/// 端侧认牌：模型输出解码（含川麻 108 张字牌/花牌重映射过滤）、排成手牌、和 Gemini 合并。
final class DetectionTests: XCTestCase {
    private func box(_ x: Double, _ y: Double, w: Double = 40, h: Double = 56) -> DetectionBox {
        DetectionBox(minX: x, minY: y, maxX: x + w, maxY: y + h)
    }

    private func row(_ notation: String, x: Double = 100, y: Double = 500, w: Double = 40, h: Double = 56, gap: Double = 2) -> [TileDetection] {
        Tile.parseList(notation).enumerated().map { i, tile in
            TileDetection(box: box(x + Double(i) * (w + gap), y, w: w, h: h), score: 0.9, label: .tile(tile))
        }
    }

    func testClassNamesAndSichuanTileSet() {
        XCTAssertEqual(Tile.all.count, 27, "川麻 108 张仅包含万/条/筒 27 种序数牌")
        XCTAssertTrue(Tile.all.allSatisfy(\.isNumbered))
        XCTAssertEqual(Suit.sichuan, [.characters, .bamboo, .dots])
        XCTAssertEqual(TileClassNames.jonChan.count, 42)
        XCTAssertEqual(TileClassNames.label(for: "5B"), .tile(Tile(.bamboo, 5)))
        XCTAssertEqual(TileClassNames.label(for: "7C"), .tile(Tile(.characters, 7)))
        XCTAssertEqual(TileClassNames.label(for: "9D"), .tile(Tile(.dots, 9)))
        XCTAssertEqual(TileClassNames.label(for: "RD"), .tile(Tile(.honors, 5)))
        XCTAssertEqual(TileClassNames.label(for: "WW"), .tile(Tile(.honors, 3)))
        XCTAssertEqual(TileClassNames.label(for: "3F"), .flower)
        XCTAssertEqual(TileClassNames.label(for: "1S"), .flower, "大写 S 是季节牌")
        XCTAssertEqual(TileClassNames.label(for: "5s"), .tile(Tile(.bamboo, 5)), "小写是我们的记法")
        XCTAssertEqual(TileClassNames.label(for: "中"), .tile(Tile(.honors, 5)))
        XCTAssertNil(TileClassNames.label(for: "back"))
    }

    func testLetterboxMapsBackToImage() {
        let lb = Letterbox(imageWidth: 1280, imageHeight: 960)
        XCTAssertEqual(lb.scale, 0.5)
        XCTAssertEqual(lb.scaledHeight, 480)
        XCTAssertEqual(lb.padY, 80)
        XCTAssertEqual(lb.padX, 0)
        let mapped = lb.toImage(DetectionBox(minX: 10, minY: 90, maxX: 30, maxY: 130))
        XCTAssertEqual(mapped, DetectionBox(minX: 20, minY: 20, maxX: 60, maxY: 100))
    }

    func testDecodePicksBestNumberedClassAndRemapsHonors() {
        // 3 个 anchor、42 类：
        // anchor 0: 5B (0.9) 与 6B (0.6) 重叠 -> 保留 5B
        // anchor 1: 102, 101 重叠被 NMS 抑制
        // anchor 2: 最高分是 RD 红中 (0.92)，次高分是 1D 一筒 (0.65) -> 川麻自动过滤字牌，取最高置信度序数牌 1筒！
        let anchors = 3
        var out = [Float](repeating: 0, count: 46 * anchors)
        func set(_ a: Int, cx: Float, cy: Float, w: Float, h: Float, cls: Int, score: Float) {
            out[a] = cx; out[anchors + a] = cy; out[2 * anchors + a] = w; out[3 * anchors + a] = h
            out[(4 + cls) * anchors + a] = score
        }
        set(0, cx: 100, cy: 100, w: 40, h: 56, cls: 20, score: 0.9)   // 5B (5条)
        set(1, cx: 102, cy: 101, w: 40, h: 56, cls: 23, score: 0.6)   // 6B，被 NMS 去掉
        set(2, cx: 300, cy: 100, w: 40, h: 56, cls: 38, score: 0.92)  // RD (红中，字牌)
        out[(4 + 2) * anchors + 2] = 0.65                             // 同一 anchor 上的 1D (1筒)
        let labels = TileClassNames.jonChan.map(TileClassNames.label(for:))
        let detections = YOLOv8Decoder.decode(out, anchors: anchors, labels: labels,
                                              letterbox: Letterbox(imageWidth: 640, imageHeight: 640), threshold: 0.5)
        XCTAssertEqual(detections.count, 2)
        XCTAssertEqual(detections[0].tile, Tile(.bamboo, 5))
        XCTAssertEqual(detections[1].tile, Tile(.dots, 1), "把一筒误检成字牌时，自动在三门序数牌内取最高置信度候选")
    }

    func testRefinementRegion() {
        let tiles = row("123456789m", x: 400, y: 900)
        let region = try! XCTUnwrap(YOLOv8Decoder.refinementRegion(for: tiles, imageWidth: 2000, imageHeight: 2000))
        XCTAssertLessThan(region.minX, 400)
        XCTAssertGreaterThan(region.maxX, 400 + 9 * 42)
        // 牌已经占满整张图，不用再裁
        XCTAssertNil(YOLOv8Decoder.refinementRegion(for: tiles, imageWidth: 420, imageHeight: 60))
    }

    func testLayoutKeepsTheHandAndDropsOtherTilesAndHonors() {
        var detections = row("1112233445566p", x: 100, y: 500).shuffled()
        detections += row("999m", x: 100 + 14 * 42 + 60, y: 500)                       // 摆在右边的碰
        detections += row("19m", x: 200, y: 100, w: 20, h: 28)                         // 远处别人的小牌
        detections += row("5s", x: 1500, y: 500)                                       // 同一高度但离得很远的散牌
        detections.append(TileDetection(box: box(100, 500), score: 0.95, label: .tile(Tile(.honors, 5)))) // 字牌误检直接丢弃
        detections.append(TileDetection(box: box(60, 580), score: 0.8, label: .flower)) // 花牌直接丢弃
        let recognition = TileLayout.recognition(from: detections)
        XCTAssertEqual(recognition.concealed.map(\.tile), Tile.parseList("1112233445566p999m"))
        XCTAssertEqual(recognition.flowerCount, 0, "川麻无花牌")
        XCTAssertTrue(recognition.notes.first?.contains("3 张") ?? false, "\(recognition.notes)")
        XCTAssertTrue(recognition.melds.isEmpty, "端侧分不出副露")
    }

    func testLayoutReadsTwoRowsTopToBottom() {
        let detections = row("4567m", x: 100, y: 560) + row("111223388p", x: 100, y: 500)
        XCTAssertEqual(TileLayout.handTiles(in: detections).compactMap(\.tile), Tile.parseList("111223388p4567m"))
    }

    private struct FakeDetector: TileDetecting {
        var detections: [TileDetection]
        func detect(in image: Data) async throws -> [TileDetection] { detections }
    }

    func testOnDeviceRecognizer() async throws {
        let recognizer = OnDeviceRecognizer(detector: FakeDetector(detections: row("1112233445566p7p")))
        let result = try await recognizer.recognize(RecognitionRequest(image: Data()))
        XCTAssertEqual(result.source, "端侧")
        XCTAssertTrue(FanCalculator.isWinningShape(result.hand))

        do {
            _ = try await OnDeviceRecognizer(detector: FakeDetector(detections: [])).recognize(RecognitionRequest(image: Data()))
            XCTFail("没找到牌要报错")
        } catch let error as RecognitionError {
            XCTAssertEqual(error, .nothingFound)
        }
    }

    func testMergeUsesGeminiMeldsAndFlagsOnlyRealDifferences() {
        // Gemini：立牌 11 张 + 碰 8筒；端侧：14 张一排（碰也当立牌读进来了），第 5 张 5万读成 6万，最右边多读一张 9筒
        var gemini = Recognition(concealed: Tile.parseList("123m 456m 789m 5p 5p"), melds: [.pung(Tile(.dots, 8))], source: "Gemini")
        gemini.concealed[4] = RecognizedTile(tile: Tile(.characters, 5))
        let onDevice = Recognition(concealed: Tile.parseList("123m 466m 789m 5p 5p 888p 9p"), source: "端侧")

        let merged = DualReadRecognizer.merge(gemini, with: onDevice)
        XCTAssertEqual(merged.melds, [.pung(Tile(.dots, 8))])
        XCTAssertEqual(merged.concealed.map(\.tile), Tile.parseList("123m 456m 789m 5p 5p 9p"))
        XCTAssertEqual(merged.concealed[4].candidates, [Tile(.characters, 5), Tile(.characters, 6)])
        XCTAssertTrue(merged.concealed[11].uncertain, "只有端侧读到的 9筒要问一句")
        XCTAssertEqual(merged.reviewCount, 2)

        // 规则引擎：5万 + 删掉 9筒 才能胡（缺条门），两处都推荐
        let resolution = RecognitionResolver.resolve(merged, context: WinContext(selfDrawn: true))
        XCTAssertEqual(resolution.recommended[4], Tile(.characters, 5))
        XCTAssertEqual(resolution.removals, [11])
        XCTAssertNotNil(resolution.result)
    }

    func testMergeNotesAMeldMisread() {
        let gemini = Recognition(concealed: Tile.parseList("123m 456m 789m 5p 5p"), melds: [.pung(Tile(.dots, 7))], source: "Gemini")
        let onDevice = Recognition(concealed: Tile.parseList("123m 456m 789m 5p 5p 7p 7p 4p"), source: "端侧")
        let merged = DualReadRecognizer.merge(gemini, with: onDevice)
        XCTAssertEqual(merged.reviewCount, 0, "副露里读得不一样不插进立牌")
        XCTAssertTrue(merged.notes.contains { $0.contains("碰 7筒") && $0.contains("4筒") }, "\(merged.notes)")
    }

    func testMergeIgnoresHiddenTilesOfConcealedKong() {
        // 暗杠扣着三张，端侧只看得到翻开的那张
        let gemini = Recognition(concealed: Tile.parseList("123m 456m 789m 5p 5p"), melds: [.kong(Tile(.dots, 9), concealed: true)], source: "Gemini")
        let onDevice = Recognition(concealed: Tile.parseList("123m 456m 789m 5p 5p 9p"), source: "端侧")
        let merged = DualReadRecognizer.merge(gemini, with: onDevice)
        XCTAssertEqual(merged.reviewCount, 0)
        XCTAssertTrue(merged.notes.isEmpty)
    }

    func testDualReadShowsOnDeviceFirstAndKeepsItWhenGeminiFails() async throws {
        let fast = MockRecognizer(name: "端侧", samples: [Recognition(concealed: Tile.parseList("1112233445566p7p"), source: "端侧")], delay: .zero)
        let previews = Box()
        let dual = DualReadRecognizer(primary: fast, secondary: OnDeviceRecognizer())  // 第二路不可用
        let result = try await dual.recognize(RecognitionRequest(image: Data())) { previews.append($0) }
        XCTAssertEqual(previews.values.count, 1)
        XCTAssertEqual(result.source, "端侧")
        XCTAssertTrue(result.notes.last?.contains("没复核上") ?? false)

        // 两路都成功时返回合并结果
        let slow = MockRecognizer(name: "Gemini", samples: [Recognition(concealed: Tile.parseList("1112233445566p7p"), source: "Gemini")], delay: .milliseconds(20))
        let merged = try await DualReadRecognizer(primary: fast, secondary: slow).recognize(RecognitionRequest(image: Data()))
        XCTAssertEqual(merged.source, "双读")
        XCTAssertEqual(merged.reviewCount, 0)
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Recognition] = []
        var values: [Recognition] { lock.lock(); defer { lock.unlock() }; return stored }
        func append(_ value: Recognition) { lock.lock(); stored.append(value); lock.unlock() }
    }
}
