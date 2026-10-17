import Foundation
import SwiftUI
import Combine
import UIKit

/// 全域播放中樞:統一監聽 Apple Music / Spotify / 識歌結果,
/// 驅動歌詞引擎、翻譯、Live Activity、Widget 快照、CarPlay、PiP 懸浮窗。
@MainActor
final class PlaybackCenter: ObservableObject {

    static let shared = PlaybackCenter()

    // MARK: - 服務

    private let appleMusic = AppleMusicService.shared
    private let spotify = SpotifyService.shared
    private let lyricsSearch = LyricsSearchService.shared
    private let translation = TranslationService.shared
    private let liveActivity = LiveActivityController()
    private let settings = SettingsStore.shared

    private var cancellables: Set<AnyCancellable> = []
    private var ticker: Timer?
    /// 最近一次活動心跳推送(播放中每 2 秒補推一次,見 tick() 內背景心跳)。
    private var lastHeartbeatPush: Date = .distantPast

    // MARK: - UI 狀態

    @Published var track: Track?
    @Published var isPlaying = false
    @Published var position: TimeInterval = 0
    @Published var lyrics: LyricsDocument?
    @Published var currentLineIndex: Int?
    @Published var lineProgress: Double = 0
    @Published var lyricsState: LyricsSearchService.SearchState = .idle
    @Published var translationState: TranslationService.State = .idle
    @Published var activeSource: MusicSource?

    /// 手動模式(識歌結果載入,非實際播放)。
    @Published private(set) var isManualMode = false

    var currentLine: LyricLine? {
        guard let index = currentLineIndex else { return nil }
        guard let lyrics, index >= 0, index < lyrics.lines.count else { return nil }
        return lyrics.lines[index]
    }

    var currentLineTranslation: String? {
        guard let index = currentLineIndex, let lyrics else { return nil }
        return lyrics.translations[index]
    }

    var nextLineText: String? {
        guard let index = currentLineIndex, let lyrics,
              index + 1 < lyrics.lines.count else { return nil }
        return lyrics.lines[index + 1].text
    }

    // MARK: - 即時活動診斷(設定頁「關於」顯示,用於判斷為何活動沒出現)

    var liveActivityAuthorized: Bool { liveActivity.authorizationEnabled }
    var liveActivityActive: Bool { liveActivity.isActive }
    var liveActivityLastError: String? { liveActivity.lastError }
    var liveActivityUpdateCount: Int { liveActivity.updateCount }

    /// 安裝內是否嵌入小工具擴充(PlugIns/*.appex)。
    /// 即時活動卡由此擴充渲染;若重簽工具把它移除,活動會建立成功(App 全綠)
    /// 但鎖定畫面永遠渲染不出來 —— 這是唯一能造成「全綠卻無卡」的安裝層原因。
    var widgetExtensionInstalled: Bool {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: plugIns.path) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".appex") }
    }

    // MARK: - 啟動

    func start() {
        guard ticker == nil else { return }

        // Apple Music 監聽
        appleMusic.onTrackChange = { [weak self] track in
            self?.syncCandidateTracks()
        }
        appleMusic.onPlaybackStateChange = { [weak self] _ in
            self?.syncCandidateTracks()
        }

        // Spotify 監聽
        spotify.onTrackChange = { [weak self] track in
            self?.syncCandidateTracks()
        }
        spotify.onPlaybackStateChange = { [weak self] _ in
            self?.syncCandidateTracks()
        }
        appleMusic.startMonitoring()

        // Spotify 連線狀態 → 記錄「曾連線」
        spotify.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    if state == .connected {
                        self.settings.spotifyConnectedOnce = true
                        self.syncCandidateTracks()
                    }
                }
            }
            .store(in: &cancellables)

        // 背景保活
        if settings.keepAliveEnabled {
            KeepAliveAudioPlayer.shared.start()
        }

        // 每秒 4 次推進歌詞時間軸
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.liveActivity.end()
            }
        }

        // 設定頁關閉即時活動 → 立刻結束
        NotificationCenter.default.addObserver(
            forName: .liveActivityForceEnd,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.liveActivity.end()
            }
        }
    }

    // MARK: - 來源解析

    private struct Candidate {
        var source: MusicSource
        var track: Track?
        var position: TimeInterval?
        var isPlaying: Bool
    }

    private func resolveCandidate() -> Candidate {
        // [背景釘住] 背景期間 Spotify App Remote 可能斷線、或來源回報陳舊資料;
        // 一旦切到陳舊來源,位置會凍結(歌詞不再跟隨)或被拆卡。
        // 一律釘住「目前顯示中的來源」—其位置由錨點+經過時間內插,斷線後仍持續推算。
        if UIApplication.shared.applicationState != .active,
           let active = activeSource, active != .recognition {
            return pinnedCandidate(for: active)
        }

        let preference = settings.sourcePreference

        switch preference {
        case .appleMusic:
            return Candidate(
                source: .appleMusic,
                track: appleMusic.lastTrack,
                position: appleMusic.playbackPosition,
                isPlaying: appleMusic.isPlaying
            )
        case .spotify:
            return Candidate(
                source: .spotify,
                track: spotify.lastTrack,
                position: spotify.playbackPosition,
                isPlaying: spotify.isPlaying
            )
        case .auto:
            // 誰在播放就顯示誰;都在播放時優先 Spotify
            let spotifyPlaying = spotify.connectionState == .connected && spotify.lastTrack != nil && spotify.isPlaying
            let applePlaying = appleMusic.lastTrack != nil && appleMusic.isPlaying
            if spotifyPlaying {
                return Candidate(source: .spotify, track: spotify.lastTrack,
                                 position: spotify.playbackPosition, isPlaying: true)
            }
            if applePlaying {
                return Candidate(source: .appleMusic, track: appleMusic.lastTrack,
                                 position: appleMusic.playbackPosition, isPlaying: true)
            }
            // 都沒在播放:沿用有曲目資訊者
            if let spotifyTrack = spotify.lastTrack, spotify.connectionState == .connected {
                return Candidate(source: .spotify, track: spotifyTrack,
                                 position: spotify.playbackPosition, isPlaying: false)
            }
            return Candidate(source: .appleMusic, track: appleMusic.lastTrack,
                             position: appleMusic.playbackPosition, isPlaying: appleMusic.isPlaying)
        }
    }

    /// 各來源有動靜時呼叫:決定要顯示哪個來源的曲目。
    private func syncCandidateTracks() {
        guard !isManualMode else { return }
        let candidate = resolveCandidate()

        // [背景守衛] 背景不拆卡(candidate 無曲目)、不換來源(陳舊來源搶奪);
        // 同來源的真實換歌照常套用,回前景時由 syncFromSettingsChange 重新對帳。
        if UIApplication.shared.applicationState != .active {
            if candidate.track == nil, track != nil { return }
            if activeSource != nil, candidate.source != activeSource { return }
        }

        let changedSource = candidate.source != activeSource
        let changedTrack = candidate.track?.id != track?.id
        let artworkChanged = candidate.track?.artworkPNG != nil && candidate.track?.artworkPNG != track?.artworkPNG

        if changedSource || changedTrack || artworkChanged {
            applyCandidate(candidate)
        } else if let track {
            // 同一首:更新播放狀態
            if isPlaying != candidate.isPlaying {
                isPlaying = candidate.isPlaying
                handlePlaybackStateChange()
            }
            if let album = candidate.track?.album, track.album == nil {
                self.track?.album = album
            }
            // ISRC 由 MusicKit 非同步補上(enrichISRC)→ 回灌到目前曲目;
            // 若歌詞尚未找到/仍在載入,帶 ISRC 重查一次(Musixmatch 用 track_isrc 精準比對)。
            if let isrc = candidate.track?.isrc, self.track?.isrc == nil {
                self.track?.isrc = isrc
                if lyrics == nil {
                    beginNewSong(self.track!)
                }
            }
        } else if candidate.track == nil, track != nil {
            // 來源清空
            applyCandidate(candidate)
        }
    }

    /// 背景釘住候選:來源與曲目維持現狀,只取該來源的推算位置/狀態。
    private func pinnedCandidate(for source: MusicSource) -> Candidate {
        switch source {
        case .spotify:
            if let position = spotify.playbackPosition {
                return Candidate(source: .spotify,
                                 track: spotify.lastTrack ?? track,
                                 position: position,
                                 isPlaying: spotify.isPlaying)
            }
            return Candidate(source: .spotify, track: track, position: position, isPlaying: isPlaying)
        case .appleMusic:
            if let amTrack = appleMusic.lastTrack {
                return Candidate(source: .appleMusic,
                                 track: amTrack,
                                 position: appleMusic.playbackPosition,
                                 isPlaying: appleMusic.isPlaying)
            }
            return Candidate(source: .appleMusic, track: track, position: position, isPlaying: isPlaying)
        default:
            return Candidate(source: source, track: track, position: position, isPlaying: isPlaying)
        }
    }

    private func applyCandidate(_ candidate: Candidate) {
        activeSource = candidate.source
        isPlaying = candidate.isPlaying
        position = candidate.position ?? 0
        isManualMode = false

        let oldTrackID = track?.id
        track = candidate.track

        if candidate.track == nil {
            lyrics = nil
            currentLineIndex = nil
            lineProgress = 0
            lyricsState = .idle
            translationState = .idle
            liveActivity.end()
            writeSnapshot(reload: true)
            CarPlayLyricsBridge.shared.trackChanged(track: nil, lyrics: nil)
            return
        }

        if candidate.track?.id != oldTrackID {
            beginNewSong(candidate.track!)
        } else {
            // 同曲更新(例如封面下載完成)
            writeSnapshot(reload: true)
            CarPlayLyricsBridge.shared.trackChanged(track: track, lyrics: lyrics)
        }
    }

    // MARK: - 換歌流程

    private func beginNewSong(_ newTrack: Track) {
        lyrics = nil
        currentLineIndex = nil
        lineProgress = 0
        lyricsState = .loading
        translationState = .idle

        // 立即反映到各顯示面
        let initialState = makeContentState()
        if settings.liveActivityEnabled {
            liveActivity.ensureActive(state: initialState)
        } else {
            liveActivity.end()
        }
        writeSnapshot(reload: true)
        CarPlayLyricsBridge.shared.trackChanged(track: newTrack, lyrics: nil)

        Task { [weak self] in
            guard let self else { return }
            let document = await self.lyricsSearch.searchLyrics(
                for: newTrack,
                musixmatchKey: self.settings.musixmatchAPIKey
            )
            guard self.track?.id == newTrack.id else { return } // 已換歌,丟棄

            if let document {
                self.lyrics = document
                self.lyricsState = .loaded(provider: document.provider)
                self.writeSnapshot(reload: true)
                CarPlayLyricsBridge.shared.trackChanged(track: self.track, lyrics: document)
                self.tick()
                self.startTranslationIfNeeded()
            } else {
                self.lyricsState = .notFound
            }
        }
    }

    private func startTranslationIfNeeded() {
        guard settings.showTranslation, let document = lyrics else {
            translationState = .idle
            return
        }
        translationState = .translating
        Task { [weak self] in
            guard let self else { return }
            let result = await self.translation.translate(document: document, targetLanguage: self.settings.targetLanguage)
            guard self.lyrics?.trackID == document.trackID else { return } // 已換歌
            self.lyrics?.translations = result
            self.translationState = self.translation.state
            self.writeSnapshot(reload: true)
            CarPlayLyricsBridge.shared.trackChanged(track: self.track, lyrics: self.lyrics)
            self.pushLineUpdates(force: true)
        }
    }

    /// 設定(來源偏好等)變更後立刻重算曲目來源。
    func syncFromSettingsChange() {
        syncCandidateTracks()
    }

    /// 強制重新查詢歌詞(使用者手動重試)。
    func refreshLyrics() {
        guard let track else { return }
        lyricsSearch.invalidateCache(for: track.id)
        beginNewSong(track)
    }

    /// 重新翻譯(語言變更後)。
    func retranslate() {
        startTranslationIfNeeded()
    }

    // MARK: - 主循環

    private func tick() {
        guard !isManualMode else {
            updateManualLine()
            return
        }

        // 更新位置
        let candidate = resolveCandidate()
        if let livePosition = candidate.position, candidate.track != nil {
            position = livePosition
        }
        if candidate.track?.id != track?.id || candidate.source != activeSource {
            syncCandidateTracks()
            return
        }
        if isPlaying != candidate.isPlaying {
            isPlaying = candidate.isPlaying
            handlePlaybackStateChange()
        }

        updateLine()
        updatePiPFrame()

        // [背景心跳] 鎖定後即使行未變,每 2 秒補推一次活動:讓進度平滑推進,
        // 且關於頁「更新:N」在鎖定後持續累積 = 背景推送存活的自證。
        if isPlaying, settings.liveActivityEnabled,
           Date().timeIntervalSince(lastHeartbeatPush) >= 2.0 {
            lastHeartbeatPush = Date()
            liveActivity.update(state: makeContentState())
        }
    }

    private func updateLine() {
        guard let lyrics, lyrics.isSynced else {
            if currentLineIndex != nil {
                currentLineIndex = nil
            }
            return
        }
        let newIndex = lyrics.line(at: position)?.index
        let newProgress = lyrics.lineProgress(at: position)

        if newIndex != currentLineIndex {
            currentLineIndex = newIndex
            lineProgress = newProgress
            pushLineUpdates(force: true)
        } else {
            lineProgress = newProgress
        }
    }

    private func updateManualLine() {
        guard let lyrics, lyrics.isSynced else { return }
        let newIndex = lyrics.line(at: position)?.index
        if newIndex != currentLineIndex {
            currentLineIndex = newIndex
            lineProgress = lyrics.lineProgress(at: position)
            pushLineUpdates(force: true)
        } else {
            lineProgress = lyrics.lineProgress(at: position)
        }
    }

    /// 把當前行推送至 Live Activity / CarPlay。
    private func pushLineUpdates(force: Bool) {
        let state = makeContentState()
        if settings.liveActivityEnabled {
            liveActivity.update(state: state)
        }
        if let index = currentLineIndex, let line = currentLine {
            CarPlayLyricsBridge.shared.lineChanged(
                index: index,
                text: line.text,
                translation: currentLineTranslation,
                nextText: nextLineText
            )
        } else {
            CarPlayLyricsBridge.shared.lineChanged(index: nil, text: nil, translation: nil, nextText: nil)
        }
        if force {
            updatePiPFrame()
        }
    }

    private func handlePlaybackStateChange() {
        // [修正] 與 pushLineUpdates 一致加上開關判斷:
        // update() 現在會在前景自我補建活動,不能在關閉即時活動時繞過設定。
        if settings.liveActivityEnabled {
            liveActivity.update(state: makeContentState())
        }
        writeSnapshot(reload: true)
        CarPlayLyricsBridge.shared.playbackStateChanged(isPlaying: isPlaying)
    }

    private func makeContentState() -> LyricsActivityAttributes.ContentState {
        LyricsActivityAttributes.ContentState(
            trackTitle: track?.title ?? "LyricFlow",
            artist: track?.artist ?? "",
            sourceName: track?.source.displayName ?? activeSource?.displayName ?? "",
            line: currentLine?.text ?? "♪",
            translation: currentLineTranslation,
            nextLine: nextLineText,
            isPlaying: isPlaying,
            lineProgress: lineProgress
        )
    }

    // MARK: - PiP

    private func updatePiPFrame() {
        guard PiPLyricsController.shared.isPiPActive else { return }
        PiPLyricsController.shared.frame = .init(
            line: currentLine?.text ?? "♪",
            translation: currentLineTranslation,
            progress: lineProgress,
            trackTitle: track.map { "\($0.title) — \($0.artist)" } ?? "LyricFlow"
        )
    }

    // MARK: - 快照

    private func writeSnapshot(reload: Bool) {
        SharedSnapshotWriter.write(
            track: track,
            lyrics: lyrics,
            position: position,
            isPlaying: isPlaying,
            lineIndex: currentLineIndex
        )
        if reload {
            SharedSnapshotWriter.reloadWidgets()
        }
    }

    // MARK: - 識歌結果載入(手動模式)

    func loadRecognizedTrack(_ recognized: Track) {
        isManualMode = true
        activeSource = .recognition
        isPlaying = false
        position = 0
        track = recognized
        lyrics = nil
        currentLineIndex = nil
        lineProgress = 0
        lyricsState = .loading
        translationState = .idle
        beginNewSong(recognized)
    }

    /// 設定變更後重建即時活動(例如使用者重新開啟)。
    func refreshLiveActivity(track: Track) {
        guard settings.liveActivityEnabled else {
            liveActivity.end()
            return
        }
        liveActivity.ensureActive(state: makeContentState())
    }

    /// 回前景時呼叫:確保即時活動存在(活動只能在 App 前景建立,
    /// 背景偵測到的換歌只會 update;若活動曾被結束,需在前景補建立)。
    func ensureLiveActivity() {
        guard settings.liveActivityEnabled, track != nil else { return }
        liveActivity.ensureActive(state: makeContentState())
    }

    /// 手動模式下跳轉位置(點擊歌詞行)。
    func seekInManualMode(to time: TimeInterval) {
        guard isManualMode else { return }
        position = max(0, time)
        updateManualLine()
        writeSnapshot(reload: true)
        pushLineUpdates(force: true)
    }

    // MARK: - 播放控制(轉發給實際來源)

    func togglePlayPause() {
        guard !isManualMode else { return }
        switch activeSource {
        case .appleMusic: appleMusic.togglePlayPause()
        case .spotify: spotify.togglePlayPause()
        default: break
        }
    }

    func nextTrack() {
        guard !isManualMode else { return }
        switch activeSource {
        case .appleMusic: appleMusic.next()
        case .spotify: spotify.next()
        default: break
        }
    }

    func previousTrack() {
        guard !isManualMode else { return }
        switch activeSource {
        case .appleMusic: appleMusic.previous()
        case .spotify: spotify.previous()
        default: break
        }
    }

    func seek(to time: TimeInterval) {
        guard !isManualMode else {
            seekInManualMode(to: time)
            return
        }
        switch activeSource {
        case .appleMusic: appleMusic.seek(to: time)
        case .spotify: spotify.seek(to: time)
        default: break
        }
        position = time
        writeSnapshot(reload: true)
        updateLine()
        pushLineUpdates(force: true)
    }
}
