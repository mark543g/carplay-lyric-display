import Foundation
import AVFoundation

/// 背景保活:以循環播放的極低音量無聲音訊維持 App 執行,
/// 讓歌詞引擎在背景(含鎖定)仍能持續接收播放進度、推送 Live Activity / 小工具更新。
///
/// 這是歌詞類 App 的標準做法:
/// - AVAudioSession 設為 `.playback` + `.mixWithOthers`,不干擾他人播放
/// - 與 Apple Music / Spotify 混音,音量趨近 0
/// - 監聽中斷/重置事件並自動恢復,避免被 iOS 暫停(否則鎖定後即時活動只停在第一句)
final class KeepAliveAudioPlayer {

    static let shared = KeepAliveAudioPlayer()

    private var player: AVAudioPlayer?
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        configureAudioSession()
        installObservers()
        beginSilentLoop()
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

    /// 若無聲循環因故停止,重新啟動(可於任意時機安全呼叫)。
    func ensureRunning() {
        guard isRunning, player?.isPlaying != true else { return }
        restart()
    }

    // MARK: - 內部

    private func beginSilentLoop() {
        do {
            let data = Self.silentWAVData(seconds: 2)
            let silentPlayer = try AVAudioPlayer(data: data)
            silentPlayer.numberOfLoops = -1
            silentPlayer.volume = 1.0   // 音量交給檔案本身的極低振幅(見 silentWAVData)
            silentPlayer.prepareToPlay()
            silentPlayer.play()
            player = silentPlayer
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func restart() {
        player?.stop()
        player = nil
        isRunning = false
        configureAudioSession()
        beginSilentLoop()
    }

    private var observers: [NSObjectProtocol] = []

    /// 中斷(來電 / 其他 App 佔用音訊)結束、或媒體服務重置後自動恢復,
    /// 避免無聲循環停掉 → App 被暫停 → 即時活動不再更新。
    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .ended {
                self.configureAudioSession()
                if self.player?.isPlaying != true { self.restart() }
            }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restart()
        })
    }

    /// 產生 n 秒的 16-bit 單聲道**極低振幅音訊**並轉為 WAV。
    ///
    /// 刻意不用「純數位靜音(全 0)」:iOS 有時會判定沒有實際音訊輸出而暫停 App,
    /// 導致背景不再更新。改用約 0.9% 振幅、30Hz 的正弦(人耳幾乎不可聞),
    /// 讓系統認定「確實在播放音訊」→ App 背景持續執行 → 即時活動能持續更新。
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

        // 低振幅正弦(約 0.9% 振幅、30Hz)→ 幾乎不可聞但為真實音訊
        let frequency = 30.0
        let amplitude = 300.0
        for sample in 0..<totalSamples {
            let value = Int16(amplitude * sin(2.0 * Double.pi * frequency * Double(sample) / Double(sampleRate)))
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 2))
        }

        return data
    }
}
