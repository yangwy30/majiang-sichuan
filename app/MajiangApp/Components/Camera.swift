import AVFoundation
import SwiftUI
import UIKit

/// 拍照页的内嵌相机。模拟器和没给相机权限时 `isAvailable` 为 false，页面退回到相册。
/// 会话状态只在 `queue` 上读写，`pending` 只在主线程，所以手动标成 Sendable。
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "majiang.camera")
    private var configured = false
    private var pending: CheckedContinuation<UIImage?, Never>?
    /// 在 `queue` 上配置好以后才有；之后只在主线程读。
    private var device: AVCaptureDevice?
    /// 取景和照片的方向跟着手机怎么拿：iPhone Duo 内屏不管 App 锁没锁竖屏都会转，
    /// 横着拿时取景不能是歪的，横着拍的一排牌在照片里也是横的。只在主线程读写。
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    static var hasCamera: Bool { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }

    /// 申请权限并开始取景。成功返回 true。
    func start() async -> Bool {
        guard Self.hasCamera else { return false }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        default: return false
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                if !self.configured { self.configure() }
                if self.configured && !self.session.isRunning { self.session.startRunning() }
                continuation.resume(returning: self.session.isRunning)
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// 拍一张。相机没开时返回 nil。`pending` 只在主线程读写。
    @MainActor
    func capture() async -> UIImage? {
        guard session.isRunning, pending == nil else { return nil }
        if let angle = rotation?.videoRotationAngleForHorizonLevelCapture,
           let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        return await withCheckedContinuation { continuation in
            pending = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    /// 取景画面每次放上屏幕时调一次（重拍时是新的一层）：画面随界面方向转正。
    @MainActor
    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        guard let device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        rotation = coordinator
        Self.apply(coordinator.videoRotationAngleForHorizonLevelPreview, to: layer)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak layer] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                if let layer { Self.apply(angle, to: layer) }
            }
        }
    }

    private static func apply(_ angle: CGFloat, to layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        configured = session.inputs.contains(input) && session.outputs.contains(output)
        if configured { self.device = device }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async {
            self.pending?.resume(returning: image)
            self.pending = nil
        }
    }
}

/// 取景画面，铺满父视图。
struct CameraPreview: UIViewRepresentable {
    var camera: CameraController

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var camera: CameraController?

        // 放进窗口以后才知道界面朝哪边
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { camera?.attach(previewLayer) }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.camera = camera
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

extension UIImage {
    /// 长边缩到 `maxSide`，减少上传大小（研究里 Gemini 会再压缩，原图太大没有用）。
    func downscaled(maxSide: CGFloat = 2048) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
