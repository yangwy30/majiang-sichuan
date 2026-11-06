import Foundation

// 端侧认牌：检测模型（YOLO 类）输出每张牌的框和类别，这里把它解码、去掉画面里别人的牌，排成手牌。
// 只是纯逻辑，跑模型的部分在 CoreMLTileDetector（只在苹果平台编译），这样 Linux 上也能测。

/// 图片像素坐标里的一个框，左上角是原点。
public struct DetectionBox: Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }

    public func offsetBy(x: Double, y: Double) -> DetectionBox {
        DetectionBox(minX: minX + x, minY: minY + y, maxX: maxX + x, maxY: maxY + y)
    }

    public func intersectionOverUnion(_ other: DetectionBox) -> Double {
        let w = max(0, min(maxX, other.maxX) - max(minX, other.minX))
        let h = max(0, min(maxY, other.maxY) - max(minY, other.minY))
        let overlap = w * h
        let union = width * height + other.width * other.height - overlap
        return union > 0 ? overlap / union : 0
    }
}

/// 检测到的一张牌。
public struct TileDetection: Hashable, Sendable {
    public enum Label: Hashable, Sendable {
        case tile(Tile)
        /// 花牌（春夏秋冬梅兰竹菊），只计数量。
        case flower
    }

    public var box: DetectionBox
    public var score: Double
    public var label: Label

    public init(box: DetectionBox, score: Double, label: Label) {
        self.box = box
        self.score = score
        self.label = label
    }

    public var tile: Tile? {
        if case .tile(let tile) = label { return tile }
        return nil
    }
}

// MARK: - 类别名

/// 模型的类别名 → 牌。模型自带类别名（Core ML 元数据里的 `names`），换模型时不用改代码。
public enum TileClassNames {
    /// Roboflow 上 Jon Chan 数据集的 42 类，端侧模型（AR麻将助手）就是按这个顺序训练的。
    /// B 条、C 万、D 饼，F/S 花牌；EW SW WW NW 东南西北，RD GD WD 中发白。
    public static let jonChan: [String] = """
        1B 1C 1D 1F 1S 2B 2C 2D 2F 2S 3B 3C 3D 3F 3S 4B 4C 4D 4F 4S 5B 5C 5D 6B 6C 6D 7B 7C 7D \
        8B 8C 8D 9B 9C 9D EW GD NW RD SW WD WW
        """.split(separator: " ").map(String.init)

    private static let honors: [String: Int] = ["EW": 1, "SW": 2, "WW": 3, "NW": 4, "RD": 5, "GD": 6, "WD": 7]
    private static let suits: [Character: Suit] = ["B": .bamboo, "C": .characters, "D": .dots]

    /// 认得 Jon Chan 的写法（`5B`、`RD`、`3F`），也认得我们自己的记法（`5s`、`中`、`flower`），认不出返回 nil。
    public static func label(for name: String) -> TileDetection.Label? {
        let name = name.trimmingCharacters(in: .whitespaces)
        if let rank = honors[name.uppercased()] { return .tile(Tile(.honors, rank)) }
        if name.count == 2, let digit = name.first?.wholeNumberValue, (1...9).contains(digit), let letter = name.last {
            if let suit = suits[letter] { return .tile(Tile(suit, digit)) }
            // 大写 F/S 是 Jon Chan 的花牌和季节牌；小写 s 是我们记法里的条子，下面按记法解析
            if letter == "F" || letter == "S" { return .flower }
        }
        if name.lowercased() == "flower" || name.lowercased() == "season" { return .flower }
        return Tile(notation: name).map { .tile($0) }
    }
}

// MARK: - 预处理的几何

/// 等比缩放到正方形输入、两边补灰（YOLO 的 letterbox）。记下缩放和偏移，好把框换算回原图。
public struct Letterbox: Hashable, Sendable {
    public let inputSize: Int
    public let scale: Double
    /// 缩放后图片在输入里的大小和位置。
    public let scaledWidth: Int
    public let scaledHeight: Int
    public let padX: Int
    public let padY: Int

    public init(imageWidth: Int, imageHeight: Int, inputSize: Int = 640) {
        self.inputSize = inputSize
        scale = Double(inputSize) / Double(max(imageWidth, imageHeight, 1))
        scaledWidth = Int((Double(imageWidth) * scale).rounded())
        scaledHeight = Int((Double(imageHeight) * scale).rounded())
        padX = (inputSize - scaledWidth) / 2
        padY = (inputSize - scaledHeight) / 2
    }

    /// 模型输入坐标 → 原图坐标。
    public func toImage(_ box: DetectionBox) -> DetectionBox {
        DetectionBox(minX: (box.minX - Double(padX)) / scale, minY: (box.minY - Double(padY)) / scale,
                     maxX: (box.maxX - Double(padX)) / scale, maxY: (box.maxY - Double(padY)) / scale)
    }
}

// MARK: - YOLOv8 输出解码

public enum YOLOv8Decoder {
    /// 解码 YOLOv8 检测头的原始输出：形状 `[4 + 类别数, anchors]`，按行存（先 anchors 个 cx，再 anchors 个 cy …）。
    /// 每个 anchor 取分数最高的类别，过阈值后做不分类别的 NMS（和 Python 版 `cv2.dnn.NMSBoxes` 一样）。
    public static func decode(_ output: UnsafeBufferPointer<Float>, anchors: Int, labels: [TileDetection.Label?],
                              letterbox: Letterbox, threshold: Double, iouThreshold: Double = 0.45) -> [TileDetection] {
        let classes = output.count / anchors - 4
        guard classes > 0, output.count == (4 + classes) * anchors else { return [] }
        var candidates: [(box: DetectionBox, score: Double, cls: Int)] = []
        for a in 0..<anchors {
            var best = -Float.infinity
            var cls = 0
            for c in 0..<classes {
                let s = output[(4 + c) * anchors + a]
                if s > best { best = s; cls = c }
            }
            guard Double(best) >= threshold else { continue }
            let cx = Double(output[a]), cy = Double(output[anchors + a])
            let w = Double(output[2 * anchors + a]), h = Double(output[3 * anchors + a])
            let box = DetectionBox(minX: cx - w / 2, minY: cy - h / 2, maxX: cx + w / 2, maxY: cy + h / 2)
            candidates.append((letterbox.toImage(box), Double(best), cls))
        }
        let kept = nonMaxSuppression(candidates.map { ($0.box, $0.score) }, iouThreshold: iouThreshold)
        return kept.compactMap { i in
            let c = candidates[i]
            guard c.cls < labels.count, let label = labels[c.cls] else { return nil }
            return TileDetection(box: c.box, score: c.score, label: label)
        }
    }

    public static func decode(_ output: [Float], anchors: Int, labels: [TileDetection.Label?],
                              letterbox: Letterbox, threshold: Double, iouThreshold: Double = 0.45) -> [TileDetection] {
        output.withUnsafeBufferPointer {
            decode($0, anchors: anchors, labels: labels, letterbox: letterbox, threshold: threshold, iouThreshold: iouThreshold)
        }
    }

    /// 按分数从高到低留框，和已留的框重叠超过阈值的丢掉。返回留下的下标。
    public static func nonMaxSuppression(_ boxes: [(box: DetectionBox, score: Double)], iouThreshold: Double) -> [Int] {
        var kept: [Int] = []
        for i in boxes.indices.sorted(by: { boxes[$0].score > boxes[$1].score }) {
            if kept.allSatisfy({ boxes[$0].box.intersectionOverUnion(boxes[i].box) <= iouThreshold }) {
                kept.append(i)
            }
        }
        return kept
    }

    /// 第一遍检测后，把牌所在的区域（四周留些边）裁出来放大再检测一遍，小牌会认得更准（照搬 majiang_calculator）。
    /// 牌已经占满大半张图时不用再裁，返回 nil。
    public static func refinementRegion(for detections: [TileDetection], imageWidth: Int, imageHeight: Int) -> DetectionBox? {
        guard !detections.isEmpty else { return nil }
        let minX = detections.map(\.box.minX).min()!, minY = detections.map(\.box.minY).min()!
        let maxX = detections.map(\.box.maxX).max()!, maxY = detections.map(\.box.maxY).max()!
        let averageHeight = detections.map(\.box.height).reduce(0, +) / Double(detections.count)
        let pad = max(averageHeight * 1.5, max(maxX - minX, maxY - minY) * 0.12)
        let w = Double(imageWidth), h = Double(imageHeight)
        let region = DetectionBox(minX: max(0, minX - pad).rounded(.down), minY: max(0, minY - pad).rounded(.down),
                                  maxX: min(w, maxX + pad).rounded(.down), maxY: min(h, maxY + pad).rounded(.down))
        if region.width > w * 0.85 && region.height > h * 0.85 { return nil }
        guard region.width >= 8, region.height >= 8 else { return nil }
        return region
    }
}

// MARK: - 排成手牌

/// 把检测到的牌排成手牌：按行分组，留下主要那一排（和挨着它、大小差不多的几排），
/// 去掉画面边上别人的牌、牌河里的散牌；每排从左到右，排与排从上到下。
/// 端侧模型分不出吃碰杠，所有牌都当立牌，副露交给 Gemini 或用户。
public enum TileLayout {
    public static func recognition(from detections: [TileDetection], source: String = "端侧") -> Recognition {
        let tiles = detections.filter { $0.tile != nil }
        let hand = handTiles(in: tiles)
        let flowers = nearbyFlowers(detections.filter { $0.label == .flower }, hand: hand)
        var recognition = Recognition(concealed: hand.compactMap(\.tile), flowerCount: flowers, source: source)
        let dropped = tiles.count - hand.count
        if dropped > 0 {
            recognition.notes.append("画面里还有 \(dropped) 张别的牌，没算进去")
        }
        return recognition
    }

    /// 花牌一般摆在手牌前后，大小和手牌差不多的才算。
    static func nearbyFlowers(_ flowers: [TileDetection], hand: [TileDetection]) -> Int {
        guard !hand.isEmpty else { return 0 }
        let tileHeight = median(hand.map(\.box.height))
        let top = hand.map(\.box.minY).min()! - 3 * tileHeight
        let bottom = hand.map(\.box.maxY).max()! + 3 * tileHeight
        return flowers.filter { (0.6...1.6).contains($0.box.height / tileHeight) && (top...bottom).contains($0.box.midY) }.count
    }

    /// 留下手牌，按阅读顺序排好（只给牌，不含花牌）。
    public static func handTiles(in detections: [TileDetection]) -> [TileDetection] {
        guard !detections.isEmpty else { return [] }
        let rows = groupIntoRows(detections)
        guard let main = rows.max(by: { ($0.count, median($0.map(\.box.height))) < ($1.count, median($1.map(\.box.height))) })
        else { return [] }
        let tileHeight = median(main.map(\.box.height))
        let tileWidth = median(main.map(\.box.width))
        let mainY = mean(main.map(\.box.midY))

        var result: [TileDetection] = []
        for row in rows {
            let isMain = row == main
            let rowHeight = median(row.map(\.box.height))
            if !isMain {
                // 大小差太多（远处别人的牌）或离得太远（牌河）的整排不要
                guard (0.65...1.5).contains(rowHeight / tileHeight),
                      abs(mean(row.map(\.box.midY)) - mainY) <= 2.5 * tileHeight else { continue }
            }
            let sized = row.filter { (0.6...1.6).contains($0.box.height / tileHeight) }
            let segments = splitByGaps(sized, maxGap: 2.5 * tileWidth)
            if isMain {
                // 主排里最长的一段是手牌；别的段至少 3 张才留（摆在旁边的吃碰杠）
                let longest = segments.max { $0.count < $1.count } ?? []
                result += segments.filter { $0 == longest || $0.count >= 3 }.flatMap { $0 }
            } else {
                result += segments.filter { $0.count >= 3 }.flatMap { $0 }
            }
        }
        return result
    }

    /// 按框的中心高度分行：和当前这一行的平均高度差不到半张牌就算同一行。行内从左到右，行从上到下。
    static func groupIntoRows(_ detections: [TileDetection]) -> [[TileDetection]] {
        let tileHeight = median(detections.map(\.box.height))
        var rows: [[TileDetection]] = []
        for detection in detections.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let last = rows.last, abs(mean(last.map(\.box.midY)) - detection.box.midY) < 0.5 * tileHeight {
                rows[rows.count - 1].append(detection)
            } else {
                rows.append([detection])
            }
        }
        return rows.map { $0.sorted { $0.box.midX < $1.box.midX } }
    }

    /// 一行里相邻两张隔得比 `maxGap` 还远就断开。输入要已经从左到右排好。
    static func splitByGaps(_ row: [TileDetection], maxGap: Double) -> [[TileDetection]] {
        var segments: [[TileDetection]] = []
        for detection in row {
            if let previous = segments.last?.last, detection.box.minX - previous.box.maxX <= maxGap {
                segments[segments.count - 1].append(detection)
            } else {
                segments.append([detection])
            }
        }
        return segments
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - 端侧识别

/// 跑检测模型的部分。App 里是 `CoreMLTileDetector`，测试里换成假的。
public protocol TileDetecting: Sendable {
    /// 检测照片（JPEG/PNG 数据）里的牌，坐标是按 EXIF 方向转正以后的像素坐标。
    func detect(in image: Data) async throws -> [TileDetection]
}
