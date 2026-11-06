#if canImport(CoreML) && canImport(ImageIO)
import CoreGraphics
import CoreML
import Foundation
import ImageIO

/// 用 Core ML 跑 YOLOv8 式的认牌检测模型：输入 `1×3×640×640`（RGB，0–1），输出 `1×(4+类别数)×anchors`。
/// 类别名从模型元数据 `names` 读（逗号分隔），没有就按 Jon Chan 的 42 类。
///
/// 用的是开源项目 AR麻将助手的模型，权重不进仓库：
/// 本地用 `tools/on-device-model/convert_coreml.py` 转好放进 App，见 app/README.md。
/// 换别的模型时只要输入输出照这个约定，这里不用改。
public final class CoreMLTileDetector: TileDetecting, @unchecked Sendable {
    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let inputSize: Int
    private let labels: [TileDetection.Label?]
    /// 第一遍找牌区域用低一点的阈值，最终结果用高一点的（照搬 majiang_calculator：0.35 / 0.5）。
    public var regionThreshold = 0.35
    public var threshold = 0.5

    /// `url` 是编译好的 `.mlmodelc`（App 里 Xcode 会把 .mlpackage 编译好放进包里）。
    public init(compiledModelAt url: URL, configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        model = try MLModel(contentsOf: url, configuration: configuration)
        let description = model.modelDescription
        guard let input = description.inputDescriptionsByName.values.first(where: { $0.type == .multiArray }),
              let output = description.outputDescriptionsByName.values.first(where: { $0.type == .multiArray }) else {
            throw RecognitionError.unavailable("端侧模型的输入输出不是预期的格式")
        }
        inputName = input.name
        outputName = output.name
        inputSize = input.multiArrayConstraint?.shape.last?.intValue ?? 640
        let metadata = description.metadata[.creatorDefinedKey] as? [String: String]
        let names = metadata?["names"].map { $0.split(separator: ",").map(String.init) } ?? TileClassNames.jonChan
        labels = names.map(TileClassNames.label(for:))
    }

    /// 编译 `.mlpackage` 或 `.mlmodel`，返回 `.mlmodelc` 的位置（Mac 上跑评测用；App 里不需要）。
    public static func compileModel(at url: URL) async throws -> URL {
        try await MLModel.compileModel(at: url)
    }

    public func detect(in data: Data) async throws -> [TileDetection] {
        guard let image = Self.uprightImage(from: data) else {
            throw RecognitionError.badResponse("照片打不开")
        }
        return try detect(image)
    }

    /// 先整张图粗找一遍牌在哪，再把牌所在区域裁出来放大重找一遍；第二遍找到的不比第一遍少就用第二遍的。
    public func detect(_ image: CGImage) throws -> [TileDetection] {
        let first = try detectOnce(image, threshold: regionThreshold)
        var result = first.filter { $0.score >= threshold }
        if let region = YOLOv8Decoder.refinementRegion(for: result, imageWidth: image.width, imageHeight: image.height),
           let crop = image.cropping(to: CGRect(x: region.minX, y: region.minY, width: region.width, height: region.height)) {
            let second = try detectOnce(crop, threshold: threshold).map {
                TileDetection(box: $0.box.offsetBy(x: region.minX, y: region.minY), score: $0.score, label: $0.label)
            }
            if second.count >= result.count { result = second }
        }
        return result
    }

    private func detectOnce(_ image: CGImage, threshold: Double) throws -> [TileDetection] {
        let letterbox = Letterbox(imageWidth: image.width, imageHeight: image.height, inputSize: inputSize)
        let input = try Self.makeInput(image, letterbox: letterbox)
        let features = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: input)])
        let prediction = try model.prediction(from: features)
        guard let output = prediction.featureValue(for: outputName)?.multiArrayValue,
              let (values, anchors) = Self.floats(output) else {
            throw RecognitionError.unavailable("端侧模型没有输出")
        }
        return YOLOv8Decoder.decode(values, anchors: anchors, labels: labels, letterbox: letterbox, threshold: threshold)
    }

    // MARK: 图片

    /// 按 EXIF 方向转正后的图片（iPhone 拍的照片像素常常是横着存的）。
    static func uprightImage(from data: Data, maxPixelSize: Int = 4096) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? maxPixelSize
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? maxPixelSize
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(width, height), maxPixelSize),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 等比缩放进 640×640，四周补灰（114），排成 CHW 的 0–1 浮点数。
    static func makeInput(_ image: CGImage, letterbox: Letterbox) throws -> MLMultiArray {
        let size = letterbox.inputSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.setFillColor(red: 114 / 255, green: 114 / 255, blue: 114 / 255, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
            context.interpolationQuality = .high
            // CGContext 的原点在左下：上边留 padY，所以 y 从 size - padY - 高度 开始
            context.draw(image, in: CGRect(x: letterbox.padX, y: size - letterbox.padY - letterbox.scaledHeight,
                                           width: letterbox.scaledWidth, height: letterbox.scaledHeight))
            return true
        }
        guard drawn else { throw RecognitionError.badResponse("照片处理失败") }

        let array = try MLMultiArray(shape: [1, 3, NSNumber(value: size), NSNumber(value: size)], dataType: .float32)
        let plane = size * size
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: 3 * plane)
        for i in 0..<plane {
            pointer[i] = Float(pixels[i * 4]) / 255
            pointer[plane + i] = Float(pixels[i * 4 + 1]) / 255
            pointer[2 * plane + i] = Float(pixels[i * 4 + 2]) / 255
        }
        return array
    }

    /// 把输出 `[1, C, anchors]` 拷成按行存的 Float 数组。输出可能有对齐用的跨度（stride），按跨度取。
    static func floats(_ array: MLMultiArray) -> ([Float], anchors: Int)? {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        guard shape.count >= 2 else { return nil }
        let channels = shape[shape.count - 2], anchors = shape[shape.count - 1]
        let channelStride = strides[strides.count - 2], anchorStride = strides[strides.count - 1]
        var values = [Float](repeating: 0, count: channels * anchors)
        if array.dataType == .float32 {
            array.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                for c in 0..<channels {
                    for a in 0..<anchors { values[c * anchors + a] = buffer[c * channelStride + a * anchorStride] }
                }
            }
        } else {
            let lead = [NSNumber](repeating: 0, count: shape.count - 2)
            for c in 0..<channels {
                for a in 0..<anchors {
                    values[c * anchors + a] = array[lead + [NSNumber(value: c), NSNumber(value: a)]].floatValue
                }
            }
        }
        return (values, anchors)
    }
}
#endif
