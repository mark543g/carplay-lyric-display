import Foundation
import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import UIKit
import QuartzCore

/// 跨 App 懸浮歌詞(畫中畫渲染器)。
///
/// 原理:以 `AVSampleBufferDisplayLayer` 當作「影片層」,
/// 用 CoreGraphics 把歌詞文字繪製成 CVPixelBuffer 佇列,
/// 再以 `AVPictureInPictureController`(sampleBuffer contentSource)啟動 PiP,
/// 即可在其他 App 之上顯示懸浮歌詞窗。
final class PiPLyricsController: NSObject, ObservableObject {

    static let shared = PiPLyricsController()

    // MARK: - 對外狀態

    @Published private(set) var isPiPActive = false
    @Published private(set) var isPiPPossible = false

    struct LyricsFrame {
        var line: String
        var translation: String?
        var progress: Double
        var trackTitle: String
    }

    /// 由 PlaybackCenter 隨時更新的當前畫格內容。
    var frame = LyricsFrame(line: "正在播放…", translation: nil, progress: 0, trackTitle: "LyricFlow")

    // MARK: - 內部

    let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var renderTimer: Timer?
    private let renderSize = CGSize(width: 1280, height: 720)

    /// 內嵌在 App 內的小預覽圖層(PiP 啟動前 layer 需在 layer 樹中)。
    lazy var previewView: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        displayLayer.frame = view.bounds
        displayLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(displayLayer)
        view.isHidden = true
        return view
    }()

    private override init() {
        super.init()
        setup()
    }

    private func setup() {
        KeepAliveAudioPlayer.shared.configureAudioSession()
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        pipController = AVPictureInPictureController(contentSource: source)
        pipController?.delegate = self
        isPiPPossible = AVPictureInPictureController.isPictureInPictureSupported()
    }

    // MARK: - 啟動 / 停止

    @discardableResult
    func start() -> Bool {
        KeepAliveAudioPlayer.shared.configureAudioSession()
        _ = previewView // 確保 layer 已掛載
        startRenderLoop()
        guard let pipController, pipController.isPictureInPicturePossible else {
            return false
        }
        pipController.startPictureInPicture()
        return true
    }

    func stop() {
        pipController?.stopPictureInPicture()
        stopRenderLoop()
    }

    // MARK: - 渲染迴圈

    private func startRenderLoop() {
        guard renderTimer == nil else { return }
        renderFrame() // 立即渲染第一格
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.renderFrame()
        }
    }

    private func stopRenderLoop() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    private func renderFrame() {
        guard let sampleBuffer = Self.makeSampleBuffer(rendering: frame, size: renderSize) else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    // MARK: - 繪製

    /// 把歌詞畫格渲染成 CMSampleBuffer。
    static func makeSampleBuffer(rendering frame: LyricsFrame, size: CGSize) -> CMSampleBuffer? {
        guard let pixelBuffer = createPixelBuffer(size: size) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let image = renderImage(frame: frame, size: size)
        guard let cgImage = image.cgImage else { return nil }
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let formatDescription = createFormatDescription(pixelBuffer) else { return nil }
        // 官方常數 CMSampleTimingInfo.invalid(全 invalid 的 timing);
        // displayLayer 依序顯示畫格,節奏由 renderTimer 控制
        var timing = CMSampleTimingInfo.invalid
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sample
        )
        guard status == kCVReturnSuccess else { return nil }
        return sample
    }

    private static func createPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }

    private static func createFormatDescription(_ buffer: CVPixelBuffer) -> CMVideoFormatDescription? {
        var formatDescription: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDescription
        )
        return status == kCVReturnSuccess ? formatDescription : nil
    }

    /// 以 UIGraphicsImageRenderer 繪製歌詞畫面。
    private static func renderImage(frame: LyricsFrame, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)

            // 背景:深色漸層
            let colors = [UIColor(white: 0.10, alpha: 1).cgColor, UIColor(white: 0.04, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: []
            )

            // 頂部:曲目名稱(小字)
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.55),
            ]
            let titleString = NSAttributedString(string: frame.trackTitle, attributes: titleAttributes)
            let titleSize = titleString.size()
            titleString.draw(
                at: CGPoint(
                    x: (size.width - titleSize.width) / 2,
                    y: 60
                )
            )

            // 中央:當前歌詞行(大字、自動換行、向上置中)
            let maxWidth = size.width * 0.82
            let lineAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let lineString = NSAttributedString(string: frame.line.isEmpty ? "♪" : frame.line, attributes: lineAttributes)
            let lineBounds = lineString.boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )

            var translationHeight: CGFloat = 0
            if let translation = frame.translation, !translation.isEmpty {
                let translationAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                ]
                let translationString = NSAttributedString(string: translation, attributes: translationAttributes)
                let translationBounds = translationString.boundingRect(
                    with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                translationHeight = translationBounds.height + 36
            }

            let totalHeight = lineBounds.height + translationHeight
            let centerY = size.height / 2 - totalHeight / 2

            lineString.draw(
                with: CGRect(x: (size.width - min(lineBounds.width, maxWidth)) / 2,
                             y: centerY,
                             width: maxWidth,
                             height: lineBounds.height + 8),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )

            // 下方:譯文
            if let translation = frame.translation, !translation.isEmpty {
                let translationAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 40, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                ]
                let translationString = NSAttributedString(string: translation, attributes: translationAttributes)
                translationString.draw(
                    with: CGRect(x: (size.width - maxWidth) / 2,
                                 y: centerY + lineBounds.height + 28,
                                 width: maxWidth,
                                 height: translationHeight),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
            }

            // 底部:卡拉 OK 進度條
            let barHeight: CGFloat = 10
            let barY = size.height - 90
            let trackRect = CGRect(x: size.width * 0.09, y: barY, width: size.width * 0.82, height: barHeight)
            let track = UIBezierPath(roundedRect: trackRect, cornerRadius: barHeight / 2)
            UIColor.white.withAlphaComponent(0.18).setFill()
            track.fill()

            let fillWidth = trackRect.width * CGFloat(min(max(frame.progress, 0), 1))
            if fillWidth > 0 {
                let fillRect = CGRect(x: trackRect.minX, y: barY, width: fillWidth, height: barHeight)
                let fill = UIBezierPath(roundedRect: fillRect, cornerRadius: barHeight / 2)
                UIColor.systemPink.withAlphaComponent(0.9).setFill()
                fill.fill()
            }

            _ = rect
        }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
// 協定方法(官方文件確認的確切簽名);除最基本三個外,
// 另外三個(可能為必要)一併實作 —— 多實作選填方法無副作用,確保一致性成立。

extension PiPLyricsController: AVPictureInPictureSampleBufferPlaybackDelegate {

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        // 歌詞 PiP 不提供播放控制;維持當前狀態
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        // 歌詞畫格由 renderTimer 持續推送;回傳 false 讓系統 UI 顯示為播放中
        false
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize renderSize: CMVideoDimensions
    ) {
        // 歌詞版面固定 1280x720 渲染,尺寸變化不需處理
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval timeInterval: CMTime,
        completion: @escaping () -> Void
    ) {
        // 快轉/倒轉對歌詞無意義;直接完成
        completion()
    }

    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        // 不禁止背景音訊(音樂本身由其他 App 播放)
        false
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPLyricsController: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        DispatchQueue.main.async { self.isPiPActive = true }
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        DispatchQueue.main.async {
            self.isPiPActive = false
            self.stopRenderLoop()
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pipLyricsDidRequestRestore, object: nil)
            completionHandler(true)
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        DispatchQueue.main.async {
            self.isPiPActive = false
            self.stopRenderLoop()
        }
    }
}

extension Notification.Name {
    static let pipLyricsDidRequestRestore = Notification.Name("pipLyricsDidRequestRestore")
}
