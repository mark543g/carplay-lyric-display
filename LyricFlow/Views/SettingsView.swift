import SwiftUI
import Translation

/// 設定頁:來源偏好、翻譯語言(含模型下載 bootstrap)、Spotify、顯示與背景、CarPlay 說明。
struct SettingsView: View {

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var center: PlaybackCenter
    @EnvironmentObject private var spotify: SpotifyService

    @State private var bootstrapConfig: TranslationSession.Configuration?
    @State private var bootstrapSource = "en"
    @State private var bootstrapDone = false

    private var bootstrapLanguages: [(code: String, name: String)] {
        [("en", "English"), ("zh-Hant", "繁體中文"), ("zh-Hans", "简体中文"),
         ("ja", "日本語"), ("ko", "한국어"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch")]
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                lyricsSection
                translationSection
                spotifySection
                displaySection
                carPlaySection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 來源偏好

    private var sourceSection: some View {
        Section {
            Picker("來源偏好", selection: $settings.sourcePreference) {
                ForEach(SourcePreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .onChange(of: settings.sourcePreference) { _, _ in
                center.syncFromSettingsChange()
            }
        } header: {
            Text("音樂來源")
        } footer: {
            Text("自動偵測:誰在播放就顯示誰;同時播放時優先 Spotify。")
        }
    }

    // MARK: - 歌詞來源

    private var lyricsSection: some View {
        Section {
            TextField("Musixmatch API Key", text: $settings.musixmatchKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            LabeledContent("LRCLIB") {
                Text("已啟用(免金鑰)").foregroundStyle(.secondary)
            }
            Button {
                center.refreshLyrics()
            } label: {
                Label("重新搜尋當前曲目歌詞", systemImage: "arrow.clockwise")
            }
            .disabled(center.track == nil)
        } header: {
            Text("歌詞來源")
        } footer: {
            Text("查詢順序:Musixmatch(ISRC / 曲目精準比對)→ LRCLIB(開源歌詞庫)。Musixmatch Key 可於 developer.musixmatch.com 申請,留空則僅使用 LRCLIB。")
        }
    }

    // MARK: - 翻譯

    private var translationSection: some View {
        Section {
            Picker("翻譯目標語言", selection: $settings.targetLanguage) {
                ForEach(TranslationService.supportedLanguages, id: \.code) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .onChange(of: settings.targetLanguage) { _, _ in
                center.retranslate()
            }

            Toggle("顯示翻譯", isOn: $settings.showTranslation)

            Picker("原文語言(模型下載用)", selection: $bootstrapSource) {
                ForEach(bootstrapLanguages, id: \.code) { language in
                    Text(language.name).tag(language.code)
                }
            }

            Button {
                bootstrapConfig = TranslationSession.Configuration(
                    source: Locale.Language(identifier: bootstrapSource),
                    target: Locale.Language(identifier: settings.targetLanguage)
                )
            } label: {
                Label("下載 \(bootstrapLanguages.first { $0.code == bootstrapSource }?.name ?? "") → \(settings.targetLanguageName) 模型", systemImage: "arrow.down.circle")
            }

            if bootstrapDone {
                Label("翻譯模型已就緒", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
        } header: {
            Text("翻譯")
        } footer: {
            Text("批次翻譯歌詞前,Apple Translation 需先安裝語言模型(離線、免費)。下載一次即可長期使用;偵測到原文語言時會自動套用。")
        }
        .translationTask($bootstrapConfig) { session in
            // 觸發語言模型下載/準備
            try? await session.prepareTranslation()
            bootstrapDone = true
        }
    }

    // MARK: - Spotify

    private var spotifySection: some View {
        Section {
            if !spotify.isSDKAvailable {
                VStack(alignment: .leading, spacing: 6) {
                    Label("SpotifyiOS SDK 尚未加入專案", systemImage: "exclamationmark.triangle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("請從 github.com/spotify/ios-sdk 下載 SpotifyiOS.xcframework,拖入 Xcode 並勾選 LyricFlow target,重新編譯後即可連線。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Spotify Client ID", text: $settings.spotifyClientID)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            LabeledContent("Redirect URI") {
                Text("lyricflow://spotify-callback")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            LabeledContent("連線狀態") {
                Text(spotifyStateText)
                    .foregroundStyle(stateColor)
                    .font(.callout.weight(.medium))
            }

            Button {
                spotify.connect(clientID: settings.spotifyClientID)
            } label: {
                Label("連線 Spotify", systemImage: "link")
            }
            .disabled(!spotify.isSDKAvailable || settings.spotifyClientID.trimmed.isEmpty)

            if let message = spotify.connectionErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Spotify")
        } footer: {
            Text("到 developer.spotify.com 建立 App,Redirect URI 填入上方的 lyricflow://spotify-callback,並把 Client ID 貼到這裡。連線時會開啟 Spotify App 進行授權。")
        }
    }

    private var spotifyStateText: String {
        switch spotify.connectionState {
        case .connected: return "已連線"
        case .connecting: return "連線中…"
        case .failed: return "連線失敗"
        case .disconnected: return "未連線"
        }
    }

    private var stateColor: Color {
        switch spotify.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    // MARK: - 顯示與背景

    private var displaySection: some View {
        Section {
            Toggle("即時活動(鎖定畫面 / 立動島 / CarPlay / Watch)", isOn: $settings.liveActivityEnabled)
            Toggle("背景保活(播放中持續更新歌詞)", isOn: $settings.keepAliveEnabled)
            Toggle("App 內懸浮歌詞", isOn: $settings.overlayEnabled)
        } header: {
            Text("顯示與背景")
        } footer: {
            Text("背景保活以趨近無聲的混音音檔維持 App 執行,讓背景仍能推播即時歌詞更新;可在通知中心完全關閉。")
        }
    }

    // MARK: - CarPlay 說明

    private var carPlaySection: some View {
        Section {
            LabeledContent("CarPlay 小工具") {
                Text("桌面小工具 size Small → CarPlay").foregroundStyle(.secondary)
            }
            LabeledContent("CarPlay 儀表板") {
                Text("即時活動自動顯示").foregroundStyle(.secondary)
            }
            LabeledContent("CarPlay App 頁") {
                Text("需要 playable-content entitlement").foregroundStyle(.secondary)
            }
            Text("iOS 26 起,支援 systemSmall 的桌面小工具會自動出現在 CarPlay(設定 → 一般 → CarPlay → 選擇車輛 → 加入 LyricFlow);即時活動會自動顯示於 CarPlay 儀表板。傳統 CarPlay App 歌詞頁(本專案內建)則需申請 CarPlay 音訊 entitlement。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("CarPlay")
        }
    }
}
