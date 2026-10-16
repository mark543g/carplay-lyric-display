# LyricFlow 交接文件

## 專案概述
- iOS 26 CarPlay 歌詞 App,repo: `https://github.com/mark543g/carplay-lyric-display.git`,branch `main`
- 使用者用 Sideloadly(免費 Apple ID)重簽 CI 產出的 unsigned IPA 安裝到 iPhone
- CI: `.github/workflows/build-ipa.yml`,build number = GitHub Actions run_number(目前到 run 32)

## 基準版本(唯一由使用者確認的事實)

- **run 26 / commit `fa22627` / artifact `LyricFlow-1.0-26-unsigned-ipa` — 使用者確認:鎖定畫面可以顯示。所有後續改動以這版為基礎。**
- 目前 main(HEAD `f556bd0`)的 Swift 程式碼與 `fa22627` 逐位相同,僅額外多:App 圖示資產 + project.yml 兩行圖示設定(`1c6494d`,不影響行為)、本文件(`f556bd0`)。main 已在基準之上,無需任何回退。
- **2026-10-17 更新:使用者重裝 run 26 後鎖定畫面也不再顯示(重開機無效);build 34(已消除 App 端全部靜默失敗點)也一樣** → 問題確定在 iOS 系統層狀態。兩個可能:(a) per-app 即時活動開關被關(可偵測,`areActivitiesEnabled` = false);(b)「Face ID 與密碼 → 鎖定時允許存取 → 即時活動」被關(無 API 可讀)。程式碼已窮盡可為之處,剩餘由 app 自行顯示與引導(build 35)。
- 補充:即時活動在 iOS **從不跳出任何「是否允許」詢問視窗**,沒有提醒屬正常現象,非症狀。

## 重要更正(2026-10-16,使用者指示)

上個 AI 留下的「核心謎團」敘事是幻想,已刪除,不可採信,包括:
- 「git bisect 已做完」:bisect 需要逐 build 實測標記好壞,從未發生。
- 「27-30 與 26 渲染程式碼相同,所以不可能是程式問題、應是使用者動了 iOS 設定」:純臆測,卻被當成結論並拿來要求使用者檢查設定。
- 「26 顯示但凍結」「27 起全壞」等測試結果記載:未經使用者證實。使用者唯一確認過的陳述是「run 26 可以顯示」。

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
- **iOS 26 + 免費簽章**:背景 update 會被 iOS 節流/不套用(Apple 論壇 748569:iOS 不支援無 APNs 的頻繁背景更新)。平台限制,無法從程式碼修復。
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

| Build | Commit | 內容(自 git 驗證) | 狀態 |
|-------|--------|------|------|
| 26 | `fa22627` | 硬化: NSSupportsLiveActivitiesFrequentUpdates, staleDate nil, keep-alive stop() 修復, ISRC 回填 | ✅ **使用者確認可以顯示(基準)** |
| 27 | `fa59916` | LA view 改 TimelineView 自渲染 + 診斷計數器 | 上個 AI 聲稱全空白;未經證實 |
| 28 | `8f5c76e` | LA view 還原為 26 版 + 診斷計數器 | 未經證實 |
| 29 | `4d88f21` | 移除 willTerminate→end(), 自我修復, 提示條, App 圖示 | 未經證實 |
| 30 | `5b1a905` | 三態提示條, SettingsView onChange 修復 | 未經證實 |
| 31 | `1c6494d` | 還原為 26 版 + 圖示,無其他改動 | CI 成功(程式碼=26+圖示) |
| 32 | `f556bd0` | 僅加入本交接文件 | CI 成功(程式碼=26+圖示) |
| 33 | `1b4d2b4` | 僅更新交接文件(基準更正) | CI 成功(程式碼=26+圖示) |
| 34 | `c65745c` | 消除 LA 三個靜默失敗點(死卡不接回、一律嘗試建立、前景自我補建) | 使用者回報:仍無卡片、無任何提醒 |
| 35 | 本次提交 | LA 被 iOS 擋下時主畫面顯示原因 + 一鍵開啟設定;關於頁註明鎖定畫面存取的系統層限制 | 建置中 |

## 已知 iOS 限制(非程式碼可修)
1. **無 APNs → 背景 LA update 被節流**:iOS 不支援無 push 的頻繁背景更新(Apple 論壇 748569 + iDownloadBlog iOS 18 節流 5-15 秒)。
2. **Activity.request 只能在前景呼叫**:背景建立會失敗。
3. **areActivitiesEnabled** 反映 iOS 設定開關,若關閉則 App 拒絕建立 LA。
4. **鎖定畫面顯示**另受「設定 → Face ID 與密碼 → 底部即時活動」控制,無 API 可讀。
5. **LA 最長顯示 12 小時**後系統自動移除。

## 下一步方向
- 基準 = `fa22627`(run 26)。所有改動從此出發,一次一項小步提交,每個 build 保持可單獨回退。
- 27-30 曾做過的變更(TimelineView、診斷計數器、自我修復、提示條)不自動重套;重套任何一項都視為新改動,先向使用者說明動機。
- 技術參考(平台事實,非對現況的推論):
  - LA 鎖定畫面由系統渲染器 per-update 渲染,不支援 TimelineView 排程。
  - 無 APNs 時背景 LA update 受 iOS 節流(免費 Apple ID 無推播)。
  - 不依賴 App 存活、不需 APNs 的逐行推進替代路徑:widget(accessoryRectangular)預生成 timeline。

## 目前 CI 狀態
- 最新:run 35(LA 被擋時主畫面自我說明 + 一鍵開啟設定)。
- 使用者實測:26(初次安裝)可顯示;26(重裝)、34 均無鎖定畫面卡片 → 指向系統層狀態。
- 下載 unsigned IPA 後以 Sideloadly(免費 Apple ID)重簽安裝。
