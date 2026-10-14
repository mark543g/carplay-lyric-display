import Foundation
import ShazamKit
import UIKit

/// 識歌模式:透過 ShazamKit `SHManagedSession` 辨識環境音樂。
///
/// iOS 26 的 Managed Session 由系統代管麥克風錄音與簽名產生,
/// App 只需 `prepare()` 後等待 `result()`。
/// 需在 App ID 上啟用 ShazamKit 功能(developer.apple.com → Identifiers)。
@MainActor
final class RecognitionService: ObservableObject {

    static let shared = RecognitionService()

    enum RecognitionState: Equatable {
        case idle
        case listening
        case matched
        case noMatch
        case failed(String)
    }

    @Published var state: RecognitionState = .idle
    @Published var recognizedTrack: Track?
    @Published var isrc: String?
    @Published var appleMusicURL: URL?

    private var sessionTask: Task<Void, Never>?

    func startListening() {
        guard state != .listening else { return }
        state = .listening
        recognizedTrack = nil
        isrc = nil
        appleMusicURL = nil

        sessionTask = Task { [weak self] in
            guard let self else { return }
            let session = SHManagedSession()
            await session.prepare()
            let result = await session.result()
            guard !Task.isCancelled else { return }

            switch result {
            case .match(let match):
                if let item = match.mediaItems.first {
                    self.state = .matched
                    self.isrc = item.isrc
                    self.appleMusicURL = item.appleMusicURL
                    var track = Track(
                        id: Track.makeID(title: item.title ?? "", artist: item.artist ?? "未知歌手", source: .recognition),
                        title: item.title ?? "",
                        artist: item.artist ?? "未知歌手",
                        album: nil,
                        duration: 0,
                        source: .recognition,
                        isrc: item.isrc
                    )
                    // 下載封面(若有)
                    if let artworkURL = item.artworkURL {
                        track.artworkPNG = await Self.downloadArtwork(from: artworkURL)
                    }
                    self.recognizedTrack = track
                } else {
                    self.state = .noMatch
                }

            case .noMatch:
                self.state = .noMatch

            case .error(let error, _):
                self.state = .failed(Self.friendlyMessage(for: error))
            }
        }
    }

    func stopListening() {
        sessionTask?.cancel()
        sessionTask = nil
        if state == .listening {
            state = .idle
        }
    }

    func reset() {
        stopListening()
        state = .idle
        recognizedTrack = nil
        isrc = nil
        appleMusicURL = nil
    }

    /// 將 ShazamKit 錯誤轉為可操作說明。
    /// 錯誤 202(matchAttemptFailed,目錄服務拒絕比對):最常見原因是
    /// App ID 未啟用 ShazamKit 功能 —— 免費 Apple ID 佈建核發不出此 capability。
    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain.localizedCaseInsensitiveContains("shazamkit"), nsError.code == 202 {
            return "Shazam 目錄比對被拒(錯誤 202):此安裝的簽章未含 ShazamKit 功能。\n"
                + "免費 Apple ID 佈建無法核發該權限;需 Apple Developer Program(付費)帳號,"
                + "並在 developer.apple.com 為 App ID 啟用 ShazamKit 後重新簽章。"
        }
        return nsError.localizedDescription
    }

    private static let maxArtworkBytes = 5 * 1024 * 1024
    private static let maxArtworkPixels = 4096 * 4096

    /// [稽核 F4 修補] 串流下載 + 大小/像素尺寸上限,防止惡意或故障來源造成記憶體耗盡。
    private static func downloadArtwork(from url: URL) async -> Data? {
        guard url.scheme == "https" else { return nil }
        do {
            let (bytes, response) = try await URLSession.shared.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            var data = Data()
            var buffer = [UInt8]()
            buffer.reserveCapacity(64 * 1024)
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    data.append(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                    if data.count > maxArtworkBytes { return nil } // 超過上限即刻中止,不落地
                }
            }
            data.append(contentsOf: buffer)

            // 驗證可解碼且像素尺寸合理,防止巨大圖檔解碼 DoS
            guard let image = UIImage(data: data) else { return nil }
            let pixels = Int(image.size.width * image.size.height * image.scale * image.scale)
            guard pixels <= maxArtworkPixels else { return nil }

            // 縮小尺寸,避免快取過大
            let target = CGSize(width: 256, height: 256)
            let renderer = UIGraphicsImageRenderer(size: target)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
            return resized.pngData()
        } catch {
            return nil
        }
    }
}
