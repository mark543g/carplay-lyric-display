import Foundation
import AVFoundation

/// 背景保活:以循環播放的極低音量無聲音訊維持 App 執行,
/// 讓歌詞引擎在背景仍能持續接收播放進度、推送 Live Activity 更新。
///
/// 這是歌詞類 App 的標準做法:
/// - AVAudioSession 設為 `.playback` + `.mixWithOthers`,不干擾他人播放
/// - 與 Apple Music / Spotify 混音,音量趨近 0
final class KeepAliveAudioPlayer {

    static let shared = KeepAliveAudioPlayer()

    private var player: AVAudioPlayer?
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        configureAudioSession()

        do {
            let data = Self.silentWAVData(seconds: 2)
            let silentPlayer = try AVAudioPlayer(data: data)
            silentPlayer.numberOfLoops = -1
            silentPlayer.volume = 0.02
            silentPlayer.prepareToPlay()
            silentPlayer.play()
            player = silentPlayer
            isRunning = true
        } catch {
            // 保活失敗不影響前景功能
            isRunning = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 設定共用的音訊 Session(PiP 懸浮歌詞也依賴此設定)。
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    /// 產生 n 秒的 16-bit 單聲道無聲 WAV(全為靜音資料)。
    static func silentWAVData(seconds: Double) -> Data {
        let sampleRate = 22050
        let totalSamples = Int(Double(sampleRate) * seconds)
        let dataSize = totalSamples * 2

        var data = Data()
        func append(_ string: String) {
            data.append(contentsOf: string.utf8)
        }
        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 4))
        }
        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 2))
        }

        append("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        appendUInt32(16)                    // fmt chunk size
        appendUInt16(1)                     // PCM
        appendUInt16(1)                     // mono
        appendUInt32(UInt32(sampleRate))    // sample rate
        appendUInt32(UInt32(sampleRate * 2))// byte rate
        appendUInt16(2)                     // block align
        appendUInt16(16)                    // bits per sample
        append("data")
        appendUInt32(UInt32(dataSize))
        data.append(Data(count: dataSize)) // 靜音(全 0)

        return data
    }
}
