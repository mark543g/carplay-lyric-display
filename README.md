# 歌詞行 LyricFlow

支援 **即時動態歌詞 + 智慧翻譯** 的 iOS App(iOS 26+)。

## 功能總覽

| 需求 | 實作 | 使用技術 |
|---|---|---|
| 鎖定畫面歌詞 | ✅ 即時活動(雙語 + 卡拉 OK 進度) | ActivityKit |
| 立動島歌詞 | ✅ 緊湊/展開/極簡三種型態 | ActivityKit DynamicIsland |
| 桌面小工具 | ✅ Small / Medium / Large | WidgetKit |
| 鎖定畫面配件 & StandBy | ✅ Inline / Rectangular / Circular | WidgetKit accessory 家族 |
| CarPlay 小工具 | ✅ Small 家族自動上 CarPlay(iOS 26 全車款) | WidgetKit + `containerBackgroundRemovable` |
| CarPlay 儀表板歌詞 | ✅ 即時活動自動顯示 | `supplementalActivityFamilies([.small])` |
| CarPlay App 歌詞頁 | ✅ 傳統模板(非 Ultra 車款) | CarPlay `CPTemplateApplicationScene` |
| 懸浮窗 | ✅ App 內拖曳浮層 + 跨 App 畫中畫懸浮 | 拖曳 overlay + `AVPictureInPictureController` |
| Apple Music | ✅ 播放監聽/控制 + ISRC 精準比對 | `MPMusicPlayerController` + MusicKit |
| Spotify | ✅ 播放監聽/控制 | Spotify App Remote SDK |
| 識歌模式 | ✅ 環境音樂辨識 | ShazamKit `SHManagedSession` |
| 智慧翻譯 | ✅ 雙語全螢幕、逐行批次翻譯、離線 | Apple Translation + `NLLanguageRecognizer` |
| 歌詞來源 | ✅ Musixmatch(ISRC 精準)→ LRCLIB(免金鑰回退) | REST API + `.lrc` 解析器 |

## 系統需求

- macOS 15 以上
- **Xcode 26**(含 iOS 26 SDK)
- **XcodeGen**(產生 .xcodeproj):`brew install xcodegen`
- 實機建議:iPhone 14 Pro 以上(iOS 26)——立動島與鎖定畫面功能需實機驗證

## 快速建置(有 Mac)

```bash
# 1. 產生 Xcode 專案
xcodegen generate

# 2. 開啟
open LyricFlow.xcodeproj
```

在 Xcode 中:

1. 選擇 **LyricFlow** target → *Signing & Capabilities* → 填入你的 Team
2. Widget target(**LyricFlowWidgets**)同樣填入 Team
3. 接上 iPhone,選擇裝置後 ⌘R 執行

## 沒有 Mac?雲端建置直接拿 IPA

本專案內建 GitHub Actions 工作流(`.github/workflows/build-ipa.yml`),
在 **GitHub 免費的雲端 macOS 建置機**上編譯並打包未簽章 IPA —— 全程不需要擁有 Mac。

### 流程

```
推送程式碼到 GitHub → Actions 自動建置 → 下載 LyricFlow-<版本>-<建置號>-unsigned-ipa
        → Windows 用 Sideloadly 以「你的 Apple ID」重簽 → USB 安裝到 iPhone
```

1. 建立 GitHub 帳號(免費),把本資料夾推上 repo
   (公有 repo 的 macOS runner 免費無限時;私有 repo 每月 2000 分鐘額度,macOS 以 10× 計費,約可建 6~8 次)
2. 推送後到 **Actions** 分頁,等 `Build Unsigned IPA` 跑完
   (工作流會自動下載 SpotifyiOS SDK、執行 xcodegen、Release 編譯、打包 IPA)
3. 點進該次執行 → **Artifacts** 區域下載 `LyricFlow-<版本>-<建置號>-unsigned-ipa`
   (內含 `LyricFlow-<版本>-<建置號>-unsigned.ipa`,例如版本 1.0、第 42 次建置即
   `LyricFlow-1.0-42-unsigned.ipa`;版號同樣顯示在 App「設定 → 關於」)
4. Windows 安裝 [Sideloadly](https://sideloadly.io)(需搭配 iTunes 或 Apple Devices 應用程式提供 USB 驅動)
   → 拖入 IPA → 登入 Apple ID → Install
5. 手機上「設定 → 一般 → VPN與裝置管理」信任你的開發者憑證後即可開啟

### 簽章方式差異

| | 免費 Apple ID | Apple Developer Program(US$99/年) |
|---|---|---|
| 安裝效期 | **7 天**(過期需重簽) | 1 年 |
| 同時安裝 App 數 | 3 個 | 無限制 |
| 識歌(ShazamKit) | ❗不支援 | ✅(後台啟用 ShazamKit) |
| CarPlay App 歌詞頁(傳統模板) | ❗不支援(免費無解) | ✅(需申請 CarPlay 音訊核准) |
| CarPlay 儀表板即時活動 | ✅ 可用(ActivityKit 不需 entitlement) | ✅ |
| 桌面/CarPlay 小工具資料 | 🔧 預設空,可救回(見下方) | ✅ |
| TestFlight 分享給朋友 | ❌ | ✅ |

免費簽章「一定可用」的功能:主 App、Apple Music 歌詞、雙語全螢幕、
智慧翻譯、**即時活動(鎖定畫面/立動島/CarPlay 儀表板)**、App 內懸浮窗、PiP 懸浮窗、Spotify(App Remote 不需特殊 entitlement)。

### 免費帳號救回小工具(含 CarPlay 小工具)

免費帳號核發的 App Group 會被 Apple 強制加上 team ID 前綴(如
`group.A1B2C3D4E5.com.lab.lyricflow`),與程式碼預設值不同,導致小工具讀不到資料。
本專案已把 group ID 做成建置參數,救法:

1. 先用 Sideloadly 簽一次(勾選/新增 App Groups),記下它**實際核發**的完整 group ID
2. GitHub repo → **Settings → Secrets and variables → Actions → Variables**
   新增 `LYRICFLOW_APP_GROUP` = 該 group ID
3. 重新觸發 `Build Unsigned IPA` 工作流(會以該值覆寫兩個 target 的 Info.plist)
4. 用 Sideloadly 重簽(同樣勾 App Groups)→ 小工具、CarPlay 小工具即有歌詞資料

⚠️ 唯一免費無解的是 **CarPlay 傳統 App 歌詞頁**(`playable-content` entitlement
僅核發給付費開發者帳號);但 CarPlay 上的**即時活動**與**小工具**兩種歌詞呈現,免費帳號都能運作。

### 想昇級到正式發佈?

1. 加入 Apple Developer Program 後,可用 Sideloadly 以付費帳號重簽(1 年效期、全 capability)
2. 未來可在 Actions 加入簽章 secrets(.p12 + 描述檔)直接產出已簽章 IPA,並自動上傳 TestFlight —— 本工作流已預留 Release 設定,改 `xcodebuild -exportArchive` 即可

> 為什麼不能直接交付現成 IPA?IPA = 已編譯的 ARM64 二進位 + **必須由你的 Apple 憑證**產生的簽章。
> Windows 機器沒有 iOS SDK 無法編譯,而簽章憑證必須屬於你的開發者身份,任何人(包括 AI)都無法替你簽。
> 上面的雲端管線把「編譯」交給 GitHub 的 Mac、「簽章」交給你的 Apple ID —— 兩件事都不需要你擁有 Mac。

## 簽章與 Capabilities

以下功能需要在 [developer.apple.com](https://developer.apple.com) 的 App ID 上啟用對應 capability,
若尚未申請,可先移除對應 key 專案仍可建置(功能退化):

| Capability | 作用 | 未啟用時 |
|---|---|---|
| App Groups(`group.com.lab.lyricflow`) | App ↔ Widget 共享歌詞快取 | 移除 entitlements 內 group 與 playable-content 後仍可跑,但小工具無內容 |
| ShazamKit | 識歌模式 | 識歌頁無法比對曲目 |
| CarPlay (Audio) `com.apple.developer.playable-content` | 傳統 CarPlay 歌詞 App 頁 | 小工具/即時活動**仍會**出現在 CarPlay(這兩者不需要 entitlement) |

`LyricFlow.entitlements` 已內建上述三把 key;若 codesign 報 capability 不符,
請在 Xcode *Signing & Capabilities* 中用 UI 重新加入(會自動修正 key 內容)。

## Spotify 整合

Spotify 官方 SDK 為二進位 framework,無法從本 repo 直接附上:

1. 到 https://github.com/spotify/ios-sdk 下載 `SpotifyiOS.xcframework`
2. 拖入 Xcode 專案,勾選 target **LyricFlow**(Embed & Sign)
3. 到 https://developer.spotify.com/dashboard 建立 App:
   - Redirect URI 填 `lyricflow://spotify-callback`
   - 勾選 **iOS SDK** / App Remote
4. 把 Client ID 貼到 App「設定 → Spotify」

> 未加入 SDK 時 App 仍可完整建置 —— Spotify 相關程式碼全部包在
> `#if canImport(SpotifyiOS)` 中,設定頁會顯示提示。

## Musixmatch(可選,建議)

- 到 https://developer.musixmatch.com 申請 API Key
- 貼到「設定 → 歌詞來源 → Musixmatch API Key」
- 有 Key 時查詢順序為 **Musixmatch(ISRC/時長精準比對)→ LRCLIB**;沒有 Key 直接走 LRCLIB

## CarPlay 測試(不需要實車)

1. 下載 **Additional Tools for Xcode**(https://developer.apple.com/download/all/)內含 **CarPlay Simulator**
2. iPhone 用 USB 接上 Mac,執行 CarPlay Simulator
3. 驗證三種呈現:
   - **小工具**:iPhone「設定 → 一般 → CarPlay → 你的車輛」加入 LyricFlow 小工具
   - **即時活動**:開始播放後自動出現在儀表板
   - **App 歌詞頁**:CarPlay 主畫面點 LyricFlow 圖示(需 CarPlay entitlement)

## 專案結構

```
├── project.yml                  # XcodeGen 定義(2 個 target)
├── Shared/                      # 同時編入 App 與 Widget
│   ├── AppConstants.swift       # App Group、Widget kind、來源列舉
│   ├── NowPlayingSnapshot.swift # 跨程序歌詞快照 + 讀寫器
│   └── LyricsActivityAttributes.swift
├── LyricFlow/                   # 主 App
│   ├── App/
│   │   ├── LyricFlowApp.swift   # 進入點(onOpenURL → Spotify 回呼)
│   │   ├── PlaybackCenter.swift # 播放中樞(狀態機 + 輸出廣播)
│   │   └── SettingsStore.swift
│   ├── Models/                  # Track、LyricLine/LyricsDocument
│   ├── Engine/LRCParser.swift   # .lrc 解析
│   ├── Services/
│   │   ├── AppleMusicService.swift      # systemMusicPlayer 監聽 + ISRC
│   │   ├── SpotifyService.swift         # App Remote(#if canImport 保護)
│   │   ├── MusixmatchProvider.swift     # matcher/subtitle/lyrics API
│   │   ├── LRCLIBProvider.swift        # get/search + 時長比對
│   │   ├── LyricsSearchService.swift    # 混合查詢 + 標題清潔
│   │   ├── RecognitionService.swift     # SHManagedSession
│   │   ├── TranslationService.swift     # Translation 框架批次翻譯
│   │   ├── LiveActivityController.swift
│   │   ├── SharedSnapshotWriter.swift   # App Group + Widget reload
│   │   ├── KeepAliveAudioPlayer.swift   # 無聲循環音檔保活
│   │   └── PiPLyricsController.swift    # 跨 App 懸浮歌詞(畫中畫)
│   ├── CarPlay/
│   │   ├── CarPlaySceneDelegate.swift   # CPTemplateApplicationScene
│   │   └── CarPlayLyricsBridge.swift
│   └── Views/                   # 首頁/全螢幕歌詞/識歌/設定/懸浮浮層
└── LyricFlowWidgets/            # Widget 擴充功能
    ├── LyricFlowWidgets.swift   # @main WidgetBundle
    ├── LyricsWidget.swift       # 桌面/鎖定/StandBy/CarPlay 小工具
    └── LyricsLiveActivity.swift # 即時活動 + 立動島
```

## 資料流

```
Apple Music / Spotify / 識歌
        │  (Track + 播放位置)
        ▼
  PlaybackCenter(每 0.25s 推進)
        │
        ├─→ LyricsSearchService ─→ Musixmatch → LRCLIB →(LyricsDocument)
        │                                    │
        ├─→ TranslationService(Apple Translation 離線批次 + App Group 快取)
        │
        ├─→ Live Activity(每行更新:鎖定畫面/立動島/CarPlay/Watch)
        ├─→ SharedSnapshotWriter(結構性變化時寫入 App Group + reload 小工具)
        │        └→ Widget Timeline:一次涵蓋整首歌的逐行條目
        ├─→ CarPlayLyricsBridge → CarPlay App 歌詞頁
        └─→ PiPLyricsController(跨 App 懸浮窗)
```

## 注意事項

- **背景更新**:「背景保活」以趨近無聲的混音音檔(`AVAudioSession .playback + .mixWithOthers`)
  維持 App 執行,播放中才能持續推送即時活動。若停用,回到前景才會更新。
- **翻譯模型**:第一次使用前,請到「設定 → 翻譯」點「下載模型」
  (觸發 `prepareTranslation()`,離線、免費)。
- **App Store 上架**:CarPlay 音訊 entitlement 需向 Apple 申請核准;
  識歌(ShazamKit)亦需在開發者後台啟用。
- **時長比對**:Musixmatch/LRCLIB 皆以曲目時長輔助比對,Spotify 廣告或
  非 English 來源偶有偏差,可用「重新搜尋歌詞」重試。

## 隱私與合規(資安稽核 F7/F8)

### 資料外送盤點(App Privacy Label 參考)

| 資料 | 接收對象 | 是否離開裝置 | 備註 |
|---|---|---|---|
| 曲目名稱/歌手/專輯/ISRC(歌詞查詢) | Musixmatch、LRCLIB | 是 | 僅查詢用,不包含使用者識別資訊 |
| 音訊指紋(識歌) | Apple Shazam 服務 | 是 | 由系統 `SHManagedSession` 代管,App 不觸碰原始麥克風音訊 |
| 歌詞翻譯 | 無 | **否** | Apple Translation 100% 端內離線運算 |
| API 憑證(Musixmatch Key / Spotify Client ID) | 無 | 否 | **儲存於 Keychain**(`AfterFirstUnlockThisDeviceOnly`),不隨備份外洩 |
| Spotify access token | 無 | 否 | 僅存 SDK 記憶體,不落地、不持久化 |
| 聆聽快照(供小工具) | 無 | 否 | App Group 本地儲存,僅含曲目資訊 |

送審 App Privacy 標籤時:無追蹤、無廣告識別碼;「資料收集」建議申報
*User Content(其他使用者內容 — 查詢用的曲目名稱)* 與 *Identifiers(App 功能相關)*,
具體依最終送審表單為準。

### 背景音訊模式送審論述( guideline 2.5.4 )

App 宣告 `audio` 背景模式的原因(建議直接引用於審核備註):

> LyricFlow 是即時歌詞顯示工具,其核心功能是在使用者於 Apple Music / Spotify
> 播放音樂的**同時**,於鎖定畫面、立動島、CarPlay 與懸浮窗持續同步顯示
> 雙語動態歌詞與卡拉 OK 進度。為了在使用者離開 App、音樂仍在前台播放時
> 繼續追蹤播放位置並更新即時活動,App 需要背景音訊執行能力。實作上採用
> `AVAudioSession` 的 `.playback + .mixWithOthers` 模式、音量趨近 0 的
> 無聲循環音檔,不干擾、不取代、不複製使用者正在播放的任何音訊內容。

若審核被拒,備案是移除背景保活(功能退化為前景更新),並將此段論述從審核備註移除。

### 安全修補記錄(2026-10 稽核)

| 編號 | 嚴重度 | 修補內容 | 位置 |
|---|---|---|---|
| F1 | 中 | 憑證自 UserDefaults 遷移至 Keychain(含一次性 legacy 遷移) | `KeychainStore.swift`、`SettingsStore.swift` |
| F2 | 中 | Spotify OAuth 回呼:驗證 `host` + 僅接受 `.connecting` 狀態期間的 callback | `SpotifyService.handleOpenURL` |
| F4 | 低 | 封面下載:https 限定、串流 5MB 上限、像素尺寸上限 | `RecognitionService.downloadArtwork` |
| F5 | 低 | 歌詞原文 512KB 上限 + LRC 標籤剝離迴圈 32 次上限 | `MusixmatchProvider`、`LRCLIBProvider`、`LRCParser` |
| F6 | 低 | App Group 建立失敗改為 DEBUG 斷言,不再靜默降級 | `AppConstants.sharedDefaults` |
| F3 | 接受 | Musixmatch API Key 必須走 URL query — API 設計限制,標記已接受風險 | — |

## 已知限制(路線圖)

- [ ] Spotify 歌詞時間偶有 ±1 秒偏移 → 可加手動校偏功能
- [ ] Live Activity 更新頻率受 ActivityKit 節流保護(~每分鐘上限)
- [ ] 歌詞快取目前使用 UserDefaults,大型歌庫可改用 SwiftData
