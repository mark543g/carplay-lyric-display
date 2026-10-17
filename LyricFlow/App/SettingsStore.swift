import Foundation
import SwiftUI
import Combine

/// 使用者設定(以 App Group UserDefaults 儲存,Widget 亦可讀取)。
@MainActor
final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    private let defaults = AppConstants.sharedDefaults

    enum Keys {
        static let sourcePreference = "sourcePreference"
        static let targetLanguage = "targetLanguage"
        static let musixmatchKey = "musixmatchKey"
        static let spotifyClientID = "spotifyClientID"
        static let liveActivityEnabled = "liveActivityEnabled"
        static let liveActivityMigrated = "liveActivityMigratedV1"
        static let keepAliveEnabled = "keepAliveEnabled"
        static let showTranslation = "showTranslation"
        static let overlayEnabled = "overlayEnabled"
        static let overlayPosition = "overlayPosition"
        static let fullScreenFontScale = "fullScreenFontScale"
        static let pipFontScale = "pipFontScale"
        static let spotifyConnectedOnce = "spotifyConnectedOnce"
    }

    @Published var sourcePreference: SourcePreference {
        didSet { defaults.set(sourcePreference.rawValue, forKey: Keys.sourcePreference) }
    }

    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: Keys.targetLanguage) }
    }

    /// [稽核 F1 修補] 敏感憑證改存 Keychain(不隨備份外洩、換機不帶走)。
    @Published var musixmatchKey: String {
        didSet { KeychainStore.save(musixmatchKey, forKey: Keys.musixmatchKey) }
    }

    @Published var spotifyClientID: String {
        didSet { KeychainStore.save(spotifyClientID, forKey: Keys.spotifyClientID) }
    }

    @Published var liveActivityEnabled: Bool {
        didSet {
            defaults.set(liveActivityEnabled, forKey: Keys.liveActivityEnabled)
            if !liveActivityEnabled {
                NotificationCenter.default.post(name: .liveActivityForceEnd, object: nil)
            }
        }
    }

    @Published var keepAliveEnabled: Bool {
        didSet {
            defaults.set(keepAliveEnabled, forKey: Keys.keepAliveEnabled)
            if keepAliveEnabled {
                KeepAliveAudioPlayer.shared.start()
            } else {
                KeepAliveAudioPlayer.shared.stop()
            }
        }
    }

    @Published var showTranslation: Bool {
        didSet { defaults.set(showTranslation, forKey: Keys.showTranslation) }
    }

    @Published var overlayEnabled: Bool {
        didSet { defaults.set(overlayEnabled, forKey: Keys.overlayEnabled) }
    }

    /// 全螢幕歌詞字體縮放(0.8 ~ 2.0,預設 1.0)。
    @Published var fullScreenFontScale: Double {
        didSet { defaults.set(fullScreenFontScale, forKey: Keys.fullScreenFontScale) }
    }

    /// 畫中畫字級縮放(0.8 ~ 2.0,預設 1.0)。
    @Published var pipFontScale: Double {
        didSet { defaults.set(pipFontScale, forKey: Keys.pipFontScale) }
    }

    /// 懸浮窗位置(normalized x/y,0~1)。
    @Published var overlayPosition: CGPoint {
        didSet {
            defaults.set("\(overlayPosition.x),\(overlayPosition.y)", forKey: Keys.overlayPosition)
        }
    }

    /// 曾經成功連線過 Spotify(下次啟動自動嘗試 reconnect)。
    @Published var spotifyConnectedOnce: Bool {
        didSet { defaults.set(spotifyConnectedOnce, forKey: Keys.spotifyConnectedOnce) }
    }

    var musixmatchAPIKey: String? {
        let key = musixmatchKey.trimmed
        return key.isEmpty ? nil : key
    }

    var targetLanguageName: String {
        TranslationService.supportedLanguages.first { $0.code == targetLanguage }?.name ?? targetLanguage
    }

    init() {
        sourcePreference = SourcePreference(
            rawValue: defaults.string(forKey: Keys.sourcePreference) ?? SourcePreference.auto.rawValue
        ) ?? .auto

        let savedLanguage = defaults.string(forKey: Keys.targetLanguage)
        targetLanguage = savedLanguage ?? "zh-Hant"

        // [稽核 F1 修補] 憑證自 Keychain 載入
        musixmatchKey = KeychainStore.load(Keys.musixmatchKey) ?? ""
        spotifyClientID = KeychainStore.load(Keys.spotifyClientID) ?? ""
        // [build 42] 鎖定畫面改以小工具呈現,即時活動預設移除:
        // 一次性遷移 — 舊裝置若曾為開,強制關閉(日後仍可從設定手動開回)。
        if defaults.object(forKey: Keys.liveActivityMigrated) == nil {
            liveActivityEnabled = false
            defaults.set(true, forKey: Keys.liveActivityMigrated)
        } else {
            liveActivityEnabled = defaults.object(forKey: Keys.liveActivityEnabled) as? Bool ?? false
        }
        keepAliveEnabled = defaults.object(forKey: Keys.keepAliveEnabled) as? Bool ?? true
        showTranslation = defaults.object(forKey: Keys.showTranslation) as? Bool ?? true
        overlayEnabled = defaults.object(forKey: Keys.overlayEnabled) as? Bool ?? false
        fullScreenFontScale = defaults.object(forKey: Keys.fullScreenFontScale) as? Double ?? 1.0
        pipFontScale = defaults.object(forKey: Keys.pipFontScale) as? Double ?? 1.0

        if let raw = defaults.string(forKey: Keys.overlayPosition),
           let x = Double(raw.components(separatedBy: ",").first ?? ""),
           let y = Double(raw.components(separatedBy: ",").dropFirst().first ?? "") {
            overlayPosition = CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        } else {
            overlayPosition = CGPoint(x: 0.5, y: 0.08)
        }

        spotifyConnectedOnce = defaults.bool(forKey: Keys.spotifyConnectedOnce)

        // 注意:Swift 規定所有儲存屬性初始化完成後才能呼叫實體方法
        // (編譯器第 8 輪指出:此呼叫必須放在 init 結尾)
        migrateLegacyCredentialsIfNeeded()
    }

    /// 舊版本曾把憑證寫進 UserDefaults:遷移至 Keychain 後立即從 UserDefaults 清除。
    private func migrateLegacyCredentialsIfNeeded() {
        for key in [Keys.musixmatchKey, Keys.spotifyClientID] {
            if let legacy = defaults.string(forKey: key), !legacy.isEmpty,
               KeychainStore.load(key) == nil {
                KeychainStore.save(legacy, forKey: key)
            }
            defaults.removeObject(forKey: key)
        }
    }

    var overlayPositionString: String {
        "\(overlayPosition.x),\(overlayPosition.y)"
    }
}

extension Notification.Name {
    /// 使用者關閉即時活動 → PlaybackCenter 立刻結束現有活動。
    static let liveActivityForceEnd = Notification.Name("liveActivityForceEnd")
}
