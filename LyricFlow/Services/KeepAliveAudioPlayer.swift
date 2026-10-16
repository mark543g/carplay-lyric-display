import Foundation
import AVFoundation
import UIKit

/// 背景保活:維持 App 在背景執行,讓歌詞引擎能持續推送 Live Activity 更新。
///
/// 依業界實務做法(Apple 開發者論壇 + App Store 上實際運作的 App):
/// - 背景模式設 `audio`(Info.plist `UIBackgroundModes`)
/// - `AVAudioSession` 設 `.playback` + `.mixWithOthers`,播放「無聲」檔案
/// - **定期(每 20 秒)重新觸發播放 + 重新啟用 Session** ← 關鍵:
///   只放一次循環音檔,iOS 過一段時間會停掉 Session 並暫停 App;
///   週期性重觸發可讓 App 在背景長時間存活,即時活動才能持續更新。
/// - 監聽中斷/重置事件並自動恢復
final class KeepAliveAudioPlayer {

    static let shared = KeepAliveAudioPlayer()

    private var player: AVAudioPlayer?
    private var refreshTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        configureAudioSession()
        installObservers()
        beginSilentLoop()
        startRefreshTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        player?.stop()
        player = nil
        isRunning = false
        // 必須一併移除中斷/媒體重置監聽:否則使用者關閉保活後,
        // 來電結束或媒體重置仍會經 restart() 偷偷喚醒無聲播放。
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 設定共用的音訊 Session(PiP 懸浮歌詞也依賴此設定)。
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    /// 若無聲循環因故停止,重新啟動。
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
            silentPlayer.volume = 0.02
            silentPlayer.prepareToPlay()
            silentPlayer.play()
            player = silentPlayer
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    private func restart() {
        guard isRunning else { return } // 已被使用者關閉 → 不得自行復活
        player?.stop()
        player = nil
        isRunning = false
        configureAudioSession()
        beginSilentLoop()
    }

    /// 每 20 秒重新啟用 Session 並重新觸發播放,避免 iOS 判定 App 閒置而暫停。
    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.keepAliveTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func keepAliveTick() {
        configureAudioSession()
        if let player {
            if player.isPlaying {
                // 重新觸發播放頭,維持「正在播放」狀態
                player.currentTime = 0
                player.play()
            } else {
                player.play()
            }
        } else {
            beginSilentLoop()
        }
    }

    /// 中斷(來電 / 其他 App 佔用音訊)結束、或媒體服務重置後自動恢復。
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
