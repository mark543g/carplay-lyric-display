import SwiftUI
import UIKit

/// 首頁:目前正在播放的曲目 + 即時雙語歌詞。
struct NowPlayingView: View {

    @EnvironmentObject private var center: PlaybackCenter
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var pip: PiPLyricsController

    @State private var showFullScreenLyrics = false
    @State private var showPiPError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    artworkSection
                    lyricSection
                    progressSection
                    transportControls
                    actionButtons
                    statusFooter
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("LyricFlow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sourceMenu
                }
            }
        }
        .fullScreenCover(isPresented: $showFullScreenLyrics) {
            FullScreenLyricsView(isPresented: $showFullScreenLyrics)
        }
        .alert("無法啟動畫中畫", isPresented: $showPiPError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("此裝置不支援畫中畫,或播放類別未生效。請確認已在背景播放狀態下重試。")
        }
        .background(pipAttachPoint)
    }

    // MARK: - 標題列

    private var header: some View {
        HStack {
            SourceBadge(source: center.activeSource)
            Spacer()
            if center.isManualMode {
                StatusCapsule(text: "識歌結果(未實際播放)", tint: .orange)
            }
        }
    }

    // MARK: - 封面與曲目

    private var artworkSection: some View {
        VStack(spacing: 12) {
            ArtworkView(artworkPNG: center.track?.artworkPNG, cornerRadius: 16)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 140)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            VStack(spacing: 4) {
                Text(center.track?.title ?? "未偵測到播放中的音樂")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(center.track?.artist ?? "開始播放 Apple Music 或 Spotify,歌詞將自動同步顯示")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 當前歌詞

    private var lyricSection: some View {
        VStack(spacing: 10) {
            switch center.lyricsState {
            case .loading:
                ProgressView("搜尋歌詞中…")
            case .notFound:
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("找不到此曲歌詞")
                        .font(.headline)
                    Text("可嘗試手動重試,或確認 Musixmatch API Key 是否正確")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("重試") { center.refreshLyrics() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 20)
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            default:
                multiLineLyrics
            }
        }
        .frame(minHeight: 150, alignment: .top)
    }

    /// 主畫面歌詞:當前行放大顯示 + 後續數行,多行呈現。
    private var multiLineLyrics: some View {
        let lines = center.lyrics?.lines ?? []
        let translations = center.lyrics?.translations ?? [:]
        let start = center.currentLineIndex ?? 0

        return VStack(alignment: .leading, spacing: 2) {
            if lines.isEmpty {
                BilingualLineView(text: "♪", translation: nil, isActive: true, fontScale: 1.35)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(0..<4, id: \.self) { offset in
                    let index = start + offset
                    if index >= 0, index < lines.count {
                        BilingualLineView(
                            text: lines[index].text,
                            translation: translations[index],
                            isActive: offset == 0,
                            fontScale: offset == 0 ? 1.35 : 1.05
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 進度

    private var progressSection: some View {
        PlaybackProgressView(
            position: center.position,
            duration: center.track?.duration ?? 0
        )
        .padding(.horizontal, 8)
    }

    // MARK: - 播放控制

    private var transportControls: some View {
        HStack(spacing: 44) {
            Button { center.previousTrack() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .disabled(center.track == nil)

            Button { center.togglePlayPause() } label: {
                Image(systemName: center.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 58))
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(center.track == nil)

            Button { center.nextTrack() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .disabled(center.track == nil)
        }
        .padding(.vertical, 6)
    }

    // MARK: - 功能按鈕

    private var actionButtons: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            actionCard(
                title: "全螢幕歌詞",
                subtitle: "雙語滾動 · 卡拉OK",
                icon: "text.book.closed.fill"
            ) {
                showFullScreenLyrics = true
            }

            actionCard(
                title: settings.overlayEnabled ? "關閉懸浮歌詞" : "懸浮歌詞(App 內)",
                subtitle: "可拖曳浮層",
                icon: settings.overlayEnabled ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
            ) {
                settings.overlayEnabled.toggle()
            }

            actionCard(
                title: pip.isPiPActive ? "關閉跨 App 懸浮窗" : "跨 App 懸浮窗",
                subtitle: "畫中畫·全螢幕之上",
                icon: pip.isPiPActive ? "pip.exit" : "pip.enter"
            ) {
                if pip.isPiPActive {
                    pip.stop()
                } else {
                    showPiPError = !pip.start()
                }
            }

            actionCard(
                title: "即時活動",
                subtitle: settings.liveActivityEnabled ? "鎖定畫面·立動島:開" : "已停用",
                icon: "sparkles.rectangle.stack.fill"
            ) {
                settings.liveActivityEnabled.toggle()
                if settings.liveActivityEnabled, let track = center.track {
                    center.refreshLiveActivity(track: track)
                }
            }
        }
    }

    private func actionCard(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 狀態頁腳

    private var statusFooter: some View {
        VStack(spacing: 6) {
            if case .loaded(let provider) = center.lyricsState {
                Text("歌詞來源:\(provider)\(center.lyrics?.isSynced == true ? "(同步)" : "(純文字)")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            switch center.translationState {
            case .translating:
                Text("智慧翻譯中…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red)
            case .needsBootstrap:
                VStack(spacing: 4) {
                    Text("翻譯模型尚未下載(\(settings.targetLanguageName))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("請到「設定 → 翻譯語言」先準備模型")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            default:
                EmptyView()
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - 來源選單

    private var sourceMenu: some View {
        Menu {
            Picker("來源偏好", selection: $settings.sourcePreference) {
                ForEach(SourcePreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - PiP layer 掛載點

    /// PiP 啟動前 AVSampleBufferDisplayLayer 需存在於 layer 樹中,
    /// 以一個隱藏的小視圖掛載。
    private var pipAttachPoint: some View {
        PiPPreviewContainer()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 承載 PiP 預覽 layer 的極小容器。
private struct PiPPreviewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        PiPLyricsController.shared.previewView
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
