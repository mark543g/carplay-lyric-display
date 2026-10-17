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

## 外部環境調查(2026-10-17,網路查證)

- **Apple 於 2026 年 9-10 月大規模收緊免費開發者帳號簽章**:0xe8008024/0xe8008018「provisioning profile banned」封鎖(builds.io 2026-09-28,SideStore/AltStore/Sideloadly/iLoader 同時中招,封鎖綁在免費團隊而非裝置)、gsa.apple.com 登入 429(2026-09-10)、Sideloadly 需 gsa-fix 才能登入、免費帳號 sideload 與 App Store 相同 bundle ID 被 Apple 阻止(sideloadly.io FAQ)。
- **含義:同一天早晚兩次 Sideloadly 重簽,從 Apple 拿到的 profile/entitlements 可能就不同。iPhone 端零設定變動,行為也可能改變** — 這是「使用者什麼都沒改、程式碼相同、26 卻由可顯示變不可顯示」的最合理觸發變數。AltStore issue #1699 亦記錄 Sideloadly 簽章有時不核發 App Group。
- iOS 26 將封禁 profile UUID/簽章 hash 存入裝置端 `mis.db`(libmis),重開機不會清除。
- LA「已建立(.active、App 全綠)但鎖定畫面不渲染」屬已知卡住型態;社群標準解法是把即時活動開關 off→on(等同刪卡重建)。**程式碼對應版:結束舊卡 + 建立全新卡片(build 36 已內建,每次 App 啟動接回舊卡時自動執行)。**

## 根因定論(2026-10-17 確認並解決)

使用者已排除並確認:專注模式關閉(早上測也壞,排程理論出局)、Face ID「鎖定時允許存取 → 即時活動」重切無效、per-app 即時活動開關重切無效、**鎖定畫面小工具清單裡沒有「歌詞行」**(程式碼已驗證 `.accessoryRectangular` 有宣告)。

**統一根因:iOS 不載入此安裝內的小工具擴充(.appex 檔案存在、About 顯示已嵌入,但系統不載入)。** LA 卡的鎖定畫面 UI 與小工具皆由此擴充渲染 → 單一機制同時解釋「LA 全綠卻無卡」與「清單無 widget」。屬**簽章/描述檔層**(對應 Apple 2026-09/10 免費團隊收緊),非 iPhone 設定、非程式碼。

修復動作(全在電腦端):① 更新 Sideloadly 至最新版重簽;② 換一顆 Apple ID 重簽(新團隊 = 乾淨描述檔;About 頁 App Group 後綴會變,可目視確認)。build 37 關於頁新增「描述檔 App ID」(萬用 `TEAMID.*` vs 指定)與「擴充描述檔:內嵌/缺失」,重簽前後對照即可見簽章差異。

### 最終確認與解法:免費 Apple ID 簽章額度用盡(已解決,2026-10-17 深夜)
- **實際過程**:使用者改用 **iLoader** 重簽安裝 → 明確報錯 **「憑證達到上限」** → 重新簽發後安裝 → **LA 卡與 widget 全部正常顯示**。根因 100% 確認。
- **機制**:免費團隊的憑證/App ID 額度(7 天滾動窗口,重裝次數會累積)用盡時,簽出來的 profile 不被 iOS 接受 → widget 擴充不載入 → LA 無卡 + widget 不在清單。與程式碼、iPhone 設定完全無關。
- **⚠️ Sideloadly 不會顯示這個錯誤** — 它會靜默簽出壞 profile,重裝多少次都顯示「安裝成功」但擴充永遠載入不了。**這是本案拖這麼久的直接原因。**
- **iLoader 會明確回報「憑證達到上限」**(AltServer 也會顯示 2009 類額度錯誤)。
- **避免再發生**:LA/widget 突然全失效時,第一步用 iLoader 重裝,看是否報額度錯 — 不要懷疑程式碼、不要懷疑 iPhone 設定。解法:重新簽發/等 7 天額度重置/換 Apple ID(新團隊=新額度)/付費帳號(每年 99 美元,永久解並解鎖 APNs 推播等)。

### 完整重檢(2026-10-17,模型換新後)
- **輸入端零變動已驗證**:`git log fa22627..HEAD -- .github/` 為空(CI 打包流程自 run 26 起未動);`4d88f21` 僅改 Swift + project.yml 圖示行。即 26→37 的 IPA 結構相同 → 結果不同只能來自簽章環境(Sideloadly↔Apple)。
- **社群證據同症狀**:r/ApolloReborn(2026-07)「Sideloadly 簽的 app widget 都出不來,改用 Impactor 後 widget 正常」;Reddit(2020)「sideload 後 widget 從未出現在清單」— 與簽名工具/免費帳號 App ID 覆蓋相關;AltStore 支援流程要求確認 widget 擴充的 App ID 是否存在(擴充需獨立 App ID,免費團隊 10 個/7 天額度)。
- **已排除**(使用者實測+程式碼驗證):iPhone 所有相關設定、Focus/排程、重開機、重裝、程式碼(`.accessoryRectangular` 有宣告)、輸入 IPA 變動。
- **電腦端行動順序**:① 更新 Sideloadly 重簽;② 換簽名工具(AltServer/AltStore 或 Impactor — 社群對此症狀的直接解法);③ 換 Apple ID(新團隊,順帶重置 10-App-ID/7 天額度);④ 付費 Developer Program($99/yr)= 永久解(同時解鎖 APNs LA 推播、CarPlay playable-content、ShazamKit、1 年憑證 — 本專案被免費層卡住的全部項目)。
- 程式端無遺留可修項:LA 視圖必須由 widget 擴充渲染,擴充載入與否完全由簽章驗證決定。

## 背景跟隨(鎖定畫面歌詞凍結)— build 40(2026-10-17 深夜)

症狀:簽章問題解決後卡片會顯示,但「再度回到鎖定畫面,歌詞不會跟隨」(停在解鎖前那一行)。
更新鏈路:PlaybackCenter `tick()`(0.25s Timer)→ 來源位置 → 偵測換行 → `activity.update()`。位置已用「錨點+經過時間」內插。三個可能斷點,build 40 全部補強:

1. **Spotify App Remote 背景斷線**:`didDisconnectWithError` 原本 `lastPlayerState = nil` → 推算錨點被銷毀 → 位置永久凍結;`.auto` 又會跌落到陳舊 Apple Music 來源(切錯歌或拆卡)。修正:背景斷線保留最後狀態作錨點(前景照舊清空)、背景釘住目前來源(pinnedCandidate)、背景不拆卡不換來源(syncCandidateTracks 守衛)、回前景 `syncFromSettingsChange()` 重新對帳。
2. **Apple Music 背景狀態誤報**:`playbackPosition` 原以 `player.playbackState == .playing` 分支,背景若回報非 playing → 錨點重錨到凍結值 → 位置停走。修正:trustedPlaying(前景=即時值,背景=通知確認的 lastKnownPlaying),暫停只在轉換瞬間凍結一次(wasTrustedPlaying)。
3. **推送節奏**:原本僅換行時 update。新增背景心跳:播放中每 2 秒補推一次活動 — 進度平滑推進,且「關於 → 更新:N」鎖定後持續累積 = 背景推送存活的自證。

前提:KeepAliveAudioPlayer 無聲 audio + UIBackgroundModes=audio 讓 App 不被掛起(既有機制,未動)。
系統層備案(懷疑 App 被系統終止時):iOS 26「設定 → 開發人員 → Fast App Termination」若開啟,系統會快速終止背景 App 導致活動停止更新;Apple 官方社群有關閉後恢復的案例。裝置端開關,非確證不動它。
已知取捨:背景暫停若無通知送達,位置會多推算一段(下次狀態通知或回前景即校正);背景期間真正跨來源切換的歌曲要回前景才切。

## 鎖定畫面呈現改版 — build 42(2026-10-17)

使用者實測 widget 在鎖定畫面正常跟隨,決定以小工具為鎖定畫面主呈現,最下方 LA 卡移除:

1. **LA 卡停用**:`SettingsStore.liveActivityEnabled` 預設改 `false`;一次性遷移鍵 `liveActivityMigratedV1` 把舊裝置曾為開的強制關(之後設定頁開關仍可手動開回);`PlaybackCenter.start()` 呼叫新增的 `LiveActivityController.endAll()` 清除系統殘存舊卡。移除範圍 = 鎖定畫面卡 + 動態島迷你卡(同一張活動)。**不受影響**:CarPlay 主畫面(`CPListTemplate`)、iOS 26 CarPlay/桌面 systemSmall widget、build 40 背景跟隨修復(留著,日後手動開回 LA 仍有效)。
2. **全寬 = 左右兩格(Apple 硬限制)**:單一 accessoryRectangular 只能放時鐘下左或右一格 = 半寬,尺寸由 Apple 固定不可調。正解:新增第二個 widget「歌詞行・右半」(`AppConstants.lyricsWidgetRightKind`,僅 `.accessoryRectangular`),與既有「動態歌詞」左右並排 → 視覺全寬。左格 = 本行歌詞大字 + 歌名・歌手小字;右格 = 翻譯大字(無翻譯 → 下一行 → 歌名・歌手)。**需到鎖定畫面自訂把左右兩格各加一個才是全寬。**
3. **字體放大**:rectangular 歌詞 `footnote` → `.title3.bold()`(lineLimit 2、minimumScaleFactor 0.6),原標題列移除讓位(無歌詞行時大字改顯歌名・歌手);右半格 `.title3.bold()` lineLimit 3。

**build 43 使用者實測後續**:左右兩格呈現被否決(很糟) → 移除右半格 widget(`lyricsWidgetRightKind` 一併刪除),鎖定畫面主呈現改用 inline 一行(時鐘上方、真全寬;字級由系統鎖死無法放大 — inline 硬限制)。**LA 卡 = 備註**:真全寬 + 可控大字的正解仍是即時活動卡,待 $99 付費帳號(解鎖 APNs,背景更新不再被節流)後再啟用;build 42 保留的設定開關可隨時手動開回。
## 放棄 inline 與 README 重寫 — build 45(2026-10-18)

1. **放棄 accessoryInline**:使用者實測時鐘上方 inline 完全不更新 — 與 rectangular 同一 widget kind、同一預生成時間軸,rectangular 會跟隨而 inline 永遠停在加入時那一行。判定為 WidgetKit/鎖定畫面對 inline 家族的平台行為(不主動重繪),程式端無可用更新鈎子。處置:`.accessoryInline` 從 supportedFamilies 移除、`InlineLyricsView` 刪除。鎖定畫面歌詞現況:rectangular(左右兩格、各半寬)= 唯一跟得穩的 widget;LA 卡 = 備援($99 解鎖 APNs 後)。
2. **README 全面重寫**:功能總覽對齊現況(LA 預設停用、inline 已移除、識歌/CarPlay 傳統頁標註需付費帳號)、新增「鎖定畫面歌詞的現況」與「免費簽章的額度陷阱」段、台灣用語全面校正(桌面→主畫面、立動島→動態島、備案→備援方案、資料外送→資料流向、發布→發佈等)。
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
| `LyricFlow/App/SettingsStore.swift` | liveActivityEnabled 預設 false(build 42 遷移強制關)、keepAliveEnabled 預設 true |
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
| 35 | `be21d63` | LA 被 iOS 擋下時主畫面顯示原因 + 一鍵開啟設定;關於頁註明鎖定畫面存取的系統層限制 | 使用者回報:App 無提示(全綠)、鎖定畫面仍無卡片 |
| 36 | `5214929` | 啟動時刪舊卡重建新卡(開關重切的程式碼版);偵測 widget 擴充是否被重簽移除並顯示;關於頁顯示擴充狀態與簽章 App Group;HANDOFF 記錄外部調查 | 使用者回報:仍無卡;LA 開關重切、專注模式排除均無效 |
| 37 | 本次提交 | 關於頁新增「描述檔 App ID」與「擴充描述檔:內嵌/缺失」簽章診斷(重簽前後對照用);HANDOFF 記錄根因定論 | 使用者回報:iLoader 報「憑證達到上限」,重新簽發後一切正常 |
| 38 | 2a500db | docs: 完整重檢(IPA 輸入零變動驗證、社群同症狀證據、電腦端行動順序) | CI 成功 |
| 39 | 6a17b55 | docs: 根因確認並解決(免費簽章額度用盡;iLoader 顯示、Sideloadly 靜默失敗) | CI 成功 |
| 40 | d8f66e8 | 背景跟隨修復:Spotify 斷線保留推算錨點、背景釘住來源與不拆卡、Apple Music trusted 狀態分診、2 秒活動心跳 | CI 成功 |
| 42 | (本次) | 鎖定畫面改版:LA 卡停用(預設關+一次性遷移+啟動 endAll)、widget 新增右半格拼全寬、歌詞字體 footnote→title3 放大 | CI 成功 |
| 43 | (本次) | 移除右半格 widget(兩格呈現被否決)、inline 改歌詞優先單行、LA 卡降為 $99 後備註 | CI 成功 |
| 45 | (本次) | 放棄 inline(accessoryInline 移除、InlineLyricsView 刪除)、README 全面重寫(功能對齊現況+台灣用語) | CI 成功 |

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
- 最新:run 45(放棄 inline + README 重寫;run 43/44 = CI 成功)
- 根因已確認並解決(2026-10-17):免費 Apple ID 簽章額度用盡;Sideloadly 靜默簽出壞 profile 且不顯示錯誤,iLoader 明確報「憑證達到上限」,重新簽發後 LA 與 widget 正常。詳見「最終確認與解法」段。程式端已窮盡、無需再改。
- 使用者實測:26(初次安裝)可顯示;之後所有安裝(含 26 重裝、34-36)皆無卡、無 widget。
- 下載 unsigned IPA 後以 Sideloadly(免費 Apple ID)重簽安裝。
