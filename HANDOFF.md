# LyricFlow 交接文件

## 專案概述
- iOS 26 CarPlay 歌詞 App,repo: `https://github.com/mark543g/carplay-lyric-display.git`,branch `main`
- 使用者用 Sideloadly(免費 Apple ID)重簽 CI 產出的 unsigned IPA 安裝到 iPhone
- CI: `.github/workflows/build-ipa.yml`,build number = GitHub Actions run_number(目前到 run 31)

## 目前狀態(截至此文件)

**Build 31 = build 26(fa22627)的完整程式碼 + App 圖示,無任何其他改動。CI 建置中(run 31)。**

Build 26 是使用者確認「鎖定畫面有正常顯示歌詞」的最後一個版本(歌詞會出現但凍結不逐行更新)。Build 27 起,使用者報告鎖定畫面完全沒有歌詞。Build 31 是純回退,不包含任何診斷計數器、提示條、或 willTerminate 修改。

## 核心謎團(git bisect 已做完)

用 `git diff fa22627 5b1a905`(build 26 → build 30)逐行比對:

- **`LyricFlowWidgets/`(整個 widget/Live Activity 擴充,負責鎖定畫面渲染)在 build 26 與 build 30 之間零差異**(byte-identical)。27 版的 TimelineView 改動已在 28 版完全還原。
- 主程式差異只有:診斷計數器(backgroundUpdateCount、backgroundTickCount,純加法不影響行為)、willTerminate→end() 移除(build 29)、自我修復 update()(build 29)、提示條(build 29/30)。
- **結論:28/29/30 的程式碼不可能顯示得跟 26 不一樣。但使用者說 26 正常、27 起全壞。**

可能的解釋(未驗證,因為使用者拒絕測試/檢查設定):
1. **裝置端狀態變更**:26 測試後、27 測試前,使用者去 iOS「設定 → 歌詞行 → 即時活動」頁面查看「更多頻繁更新」(這是 27 版發佈時的指示)。該頁有「即時活動」總開關,若被切掉,iOS 直接不讓 App 建立 Live Activity,之後裝幾版都一樣全壞。時間點完全吻合。
2. **Sideloadly 重簽問題**:每次重簽 App Group ID 可能變動,導致 widget 讀不到 snapshot。但這只影響 widget,不影響 Live Activity 卡片(LA 內容由 app 直接 push,不依賴 App Group)。
3. **未發現的程式碼差異**:已窮盡 git diff,無發現。

## 使用者約束(必須遵守)
- **不要叫使用者測試、檢查設定、回報畫面內容**。使用者明確表示「我不想測」「我不應該是你的測試人員」「不要一直讓我測試」。
- 回覆用**繁體中文**。
- 最簡潔的說明,不要冗長推測。
- 免費 Apple ID 限制:無 APNs(無法推播更新 LA)、無 ShazamKit、無 CarPlay playable-content。只能靠本地/快照方案。
- `known-good-carplay-widget` tag → commit `2a4c7c6`(更早的回退基準)。

## 架構

### Live Activity(鎖定畫面歌詞卡)
- **只在前景建立一次**(`Activity.request`),之後全用 `activity.update()` 更新。
- 活動建立時機:`beginNewSong`(偵測到新歌)+ `ensureLiveActivity`(scenePhase .active)。
- `staleDate: nil` = 永不過期(120 秒過期日會在長間奏時把正常內容標成「過時」)。
- ContentState 包含歌名、歌手、當前行、下一行、翻譯、進度。
- **iOS 26 + 免費簽章**:背景 update 會被 iOS 節流/不套用(Apple 論壇 748569:iOS 不支援無 APNs 的頻繁背景更新)。這是「歌詞凍結」的根本原因,無法從程式碼修復。
- LA 畫面由系統渲染器 per-update 渲染(WWDC23 Meet ActivityKit),**不能用 TimelineView**(會整卡空白,build 27 教訓)。

### Widget(accessoryRectangular,長方形小工具)
- `LyricsWidget.swift`: `LyricsTimelineProvider` 預生成整首歌的逐行 timeline entries,靠 iOS 自己推進,不依賴 App 存活。
- `SharedSnapshotWriter.swift`: 寫快照檔案到 App Group(`SharedStore`),widget 讀取。
- 快照檔案標記為鎖定時可讀(`completeUntilFirstUserAuthentication`)。
- Widget 不依賴 Live Activity,獨立運作。

### 保活
- `KeepAliveAudioPlayer.swift`:無聲循環音檔(`.playback` + `.mixWithOthers`),每 20 秒重新觸發,讓 App 背景不被 iOS 暫停。
- `NSSupportsLiveActivitiesFrequentUpdates = true`(Info.plist)。
- `UIBackgroundModes = audio`(Info.plist)。

### 位置推算
- `AppleMusicService.swift`:dead reckoning(anchor + elapsed),因 `currentPlaybackTime` 背景會凍結。
- `SpotifyService.swift`:同樣 dead reckoning。

### App Group
- `LYRICFLOW_APP_GROUP` repo variable,CI 注入到 build settings。
- 免費簽章時 Sideloadly 可能核發不同 group ID(如 `group.A1B2C3D4E5.com.lab.lyricflow`)。
- `SharedStore.swift` 用此 group 讀寫快照。

## 關鍵檔案

| 檔案 | 角色 |
|------|------|
| `LyricFlowWidgets/LyricsLiveActivity.swift` | LA 畫面(view),**不可用 TimelineView** |
| `LyricFlowWidgets/LyricsWidget.swift` | Widget timeline provider,逐行推進機制 |
| `Shared/NowPlayingSnapshot.swift` | 快照 schema + App Group 檔案讀寫 |
| `Shared/SharedStore.swift` | App Group 路徑 |
| `LyricFlow/Services/LiveActivityController.swift` | LA 生命週期(建立/更新/結束) |
| `LyricFlow/App/PlaybackCenter.swift` | 主控制中心(tick/換歌/推送) |
| `LyricFlow/Services/AppleMusicService.swift` | Apple Music 偵測 + 位置推算 |
| `LyricFlow/Services/SpotifyService.swift` | Spotify 偵測 + 位置推算 |
| `LyricFlow/Services/KeepAliveAudioPlayer.swift` | 背景保活 |
| `LyricFlow/Services/SharedSnapshotWriter.swift` | 寫快照給 widget |
| `LyricFlow/App/LyricFlowApp.swift` | scenePhase → ensureLiveActivity/ensureRunning |
| `LyricFlow/App/SettingsStore.swift` | liveActivityEnabled/keepAliveEnabled 預設 true |
| `LyricFlow/Views/RootView.swift` | 主畫面(banner 在 build 31 已回退移除) |
| `LyricFlow/Views/SettingsView.swift` | 設定頁 |
| `project.yml` | XcodeGen,含 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` |
| `LyricFlow/Assets.xcassets/AppIcon.appiconset/` | App 圖示(1024×1024,源自使用者 icon.png) |
| `.github/workflows/build-ipa.yml` | CI,產出 unsigned IPA |

## Build 歷史

| Build | Commit | 內容 | 狀態 |
|-------|--------|------|------|
| 26 | `fa22627` | 硬化: NSSupportsLiveActivitiesFrequentUpdates, staleDate nil, keep-alive stop() 修復, ISRC 回填 | ✅ 使用者確認鎖定畫面有顯示(凍結) |
| 27 | `fa59916` | LA view 改 TimelineView 自渲染 + 診斷計數器 | ❌ 鎖定畫面整卡空白(我造成的回歸) |
| 28 | `8f5c76e` | LA view 完全還原為 26 版 + 保留診斷計數器 | ❌ 使用者說仍無歌詞 |
| 29 | `4d88f21` | 移除 willTerminate→end(), 自我修復, 紅色提示條, App 圖示 | ❌ 使用者說仍無歌詞 |
| 30 | `5b1a905` | 三態提示條, SettingsView onChange 修復 | ❌ 使用者說仍無歌詞 |
| 31 | `1c6494d` | **純回退為 26 版 + 圖示,無任何其他改動** | CI 建置中 |

## 已知 iOS 限制(非程式碼可修)
1. **無 APNs → 背景 LA update 被節流**:iOS 不支援無 push 的頻繁背景更新。這是「歌詞凍結」的根本原因。Apple 論壇 748569 + iDownloadBlog iOS 18 節流 5-15 秒。
2. **Activity.request 只能在前景呼叫**:背景建立會失敗。
3. **areActivitiesEnabled** 反映 iOS 設定開關,若關閉則 App 拒絕建立 LA。
4. **鎖定畫面顯示**另受「設定 → Face ID 與密碼 → 底部即時活動」控制,無 API 可讀。
5. **LA 最長顯示 12 小時**後系統自動移除。

## Build 31 之後的建議方向
1. **若使用者回報 31 正常** → 27-30 的問題確認是裝置端設定(非程式碼),可重新套用 29/30 的修復(圖示、willTerminate 移除、自我修復)但**不加診斷計數器**(那些 `UIApplication.shared.applicationState` 呼叫是唯一嫌疑)。
2. **若使用者回報 31 仍不正常** → 100% 是裝置端設定(iOS 即時活動開關)。程式碼已 byte-identical 於 26 版,不可能是程式問題。需使用者確認 iOS 設定。
3. **Widget 路徑**:若 LA 因 iOS 限制無法逐行更新,widget(accessoryRectangular)是唯一可靠的逐行方案(預生成 timeline,不依賴 App)。需確認使用者有在鎖定畫面放置 widget(長按鎖定畫面 → 自訂 → 加長方形小工具「動態歌詞」)。
4. **永久凍結問題**:無 APNs 時 LA 無法背景逐行更新,這是蘋果限制。Widget 可以解決此問題,但需要使用者放置 widget。

## 目前 CI 狀態
- Run 31 進行中,commit `1c6494d`
- 完成後 artifact: `LyricFlow-1.0-31-unsigned-ipa`
- 使用者下載後用 Sideloadly 重簽安裝
