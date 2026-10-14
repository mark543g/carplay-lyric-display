import Foundation

/// 專案共用常數 —— 主 App 與 Widget 擴充功能都會編入此檔。
public enum AppConstants {
    /// App Group identifier:主 App、Widget、Live Activity 之間共享資料。
    ///
    /// 預設 `group.com.lab.lyricflow`;可由建置參數 `LYRICFLOW_APP_GROUP` 覆寫
    /// (寫入兩個 target 的 Info.plist `AppGroupIdentifier` 鍵)。
    /// 用途:免費 Apple ID 簽章時,Sideloadly 核發的 App Group 會被強制加上
    /// team ID 前綴(如 `group.A1B2C3D4E5.com.lab.lyricflow`),
    /// 把本值設成 Sideloadly 實際核發的 group 後重新建置,小工具即可取得資料。
    public static let appGroupID: String = {
        // 先讀 Info.plist 注入值(未設定時為未展開的 $(...) 原文,視為無效)
        if let injected = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
           !injected.isEmpty, !injected.contains("$(") {
            return injected
        }
        return "group.com.lab.lyricflow"
    }()

    /// 桌面小工具的 kind(WidgetKit 註冊用)。
    public static let lyricsWidgetKind = "com.lab.lyricflow.lyrics"

    /// SharedStore(UserDefaults)suite 名稱。
    ///
    /// [稽核 F6 修補] suite 建立失敗(通常是 entitlement 未宣告 App Group)
    /// 過去會靜默降級到 .standard,掩蓋設定錯誤 → Debug build 加入斷言及早暴露。
    public static var sharedDefaults: UserDefaults {
        let suite = UserDefaults(suiteName: appGroupID)
        #if DEBUG
        assert(suite != nil, "App Group '\(appGroupID)' 初始化失敗:請確認主 App 與 Widget 的 Entitlements 皆已宣告此 group")
        #endif
        return suite ?? .standard
    }

    /// Spotify App Remote 的 redirect URI scheme。
    public static let spotifyRedirectScheme = "lyricflow"
    public static var spotifyRedirectURL: URL {
        URL(string: "\(spotifyRedirectScheme)://spotify-callback")!
    }
}

/// 音樂來源。
public enum MusicSource: String, Codable, CaseIterable, Sendable {
    case appleMusic
    case spotify
    case recognition

    public var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .recognition: return "識歌結果"
        }
    }
}

/// 來源偏好(自動 = 兩邊都有播放時優先 Spotify)。
public enum SourcePreference: String, Codable, CaseIterable, Sendable {
    case auto
    case appleMusic
    case spotify

    public var displayName: String {
        switch self {
        case .auto: return "自動偵測"
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}
