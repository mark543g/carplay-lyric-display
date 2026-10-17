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
    public static let appGroupID: String = resolveAppGroupID()

    /// 解析真正可共享的 App Group。
    ///
    /// 免費 Apple ID + Sideloadly 簽章時,Apple 會把核發的 group 加上 team 前綴
    /// (例:`group.A1B2C3D4E5.com.lab.lyricflow`),與建置注入值不同,
    /// 導致主 App 與 widget 各自寫入「非共享」的 suite → widget 永遠讀不到快照。
    /// 這裡改用「確實可取得共享容器」的 group,否則從本次簽章內嵌的
    /// `embedded.mobileprovision` 取出真正核發的 group。
    private static func resolveAppGroupID() -> String {
        // 建置時注入值(CI 以 LYRICFLOW_APP_GROUP 覆寫;未展開的 $(...) 視為無效)
        let injected = (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
            .flatMap { ($0.isEmpty || $0.contains("$(")) ? nil : $0 }

        // 1) 注入值若確實被授權(能取得共享容器)→ 採用
        if let injected,
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: injected) != nil {
            return injected
        }

        // 2) 免費/開發簽章:從 embedded.mobileprovision 取實際核發的 group
        if let provisioned = provisionedAppGroupID(),
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: provisioned) != nil {
            return provisioned
        }

        // 3) 退回注入值或預設(無法共享時,主 App 仍可獨立運作)
        return injected ?? "group.com.lab.lyricflow"
    }

    /// 解析內嵌 provisioning profile(免費/開發簽章會內嵌)取得 plist。
    private static func provisionedAppGroupID() -> String? {
        guard let entitlements = embeddedProfilePlist(bundleURL: Bundle.main.bundleURL)?["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String],
              let first = groups.first else { return nil }
        return first
    }

    /// 讀取指定 bundle 內嵌的 provisioning profile plist(無則 nil)。
    ///
    /// 診斷用:主 App 與小工具擴充(.appex)各自內嵌的描述檔,是
    /// iOS 決定要不要載入擴充的依據。免費 Apple ID + Sideloadly 簽章下,
    /// Apple 2026-09/10 收緊後可能只核發涵蓋主 App 的描述檔 →
    /// 擴充不被載入 → 即時活動卡無人渲染 + 小工具清單裡看不到本 App。
    private static func embeddedProfilePlist(bundleURL: URL) -> [String: Any]? {
        let url = bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<plist"),
              let end = raw.range(of: "</plist>") else { return nil }

        let plistString = String(raw[start.lowerBound..<end.upperBound])
        guard let plistData = plistString.data(using: .utf8),
              let plistAny = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let plist = plistAny as? [String: Any] else { return nil }
        return plist
    }

    /// 主 App 描述檔的 application-identifier
    /// (如 `TEAMID.com.lab.lyricflow` 指定型,或 `TEAMID.*` 萬用型 —
    /// 萬用型才可能涵蓋小工具擴充的 bundle ID)。
    public static var mainAppApplicationIdentifier: String? {
        guard let entitlements = embeddedProfilePlist(bundleURL: Bundle.main.bundleURL)?["Entitlements"] as? [String: Any] else { return nil }
        return entitlements["application-identifier"] as? String
    }

    /// 小工具擴充(.appex)本身是否內嵌描述檔(缺失 = iOS 不載入擴充,
    /// 即時活動與小工具都無法顯示)。
    public static var widgetExtensionProfileEmbedded: Bool {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: plugIns.path),
              let appex = contents.first(where: { $0.hasSuffix(".appex") }) else { return false }
        return embeddedProfilePlist(bundleURL: plugIns.appendingPathComponent(appex, isDirectory: true)) != nil
    }

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
