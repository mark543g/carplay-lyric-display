import Foundation
import SwiftUI
#if canImport(SpotifyiOS)
import SpotifyiOS
#endif

/// Spotify App Remote 整合。
///
/// 真實 SDK(SpotifyiOS.xcframework)未加入專案時,本類仍可編譯:
/// 所有 SDK 呼叫都包在 `#if canImport(SpotifyiOS)` 中,對外維持相同介面,
/// 並以 `isSDKAvailable` 表示 SDK 是否可用(設定頁會提示如何加入)。
///
/// 加入 SDK 的方式見 README:從 https://github.com/spotify/ios-sdk 下載
/// SpotifyiOS.xcframework 後拖入 Xcode 專案(勾選 LyricFlow target)。
@MainActor
final class SpotifyService: NSObject, ObservableObject {

    static let shared = SpotifyService()

    // MARK: - 對外狀態

    var isSDKAvailable: Bool {
        #if canImport(SpotifyiOS)
        return true
        #else
        return false
        #endif
    }

    enum ConnectionState: String {
        case disconnected
        case connecting
        case connected
        case failed
    }

    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectionErrorMessage: String?

    /// 換歌 / 狀態改變回呼(主執行緒)。
    var onTrackChange: ((Track?) -> Void)?
    var onPlaybackStateChange: ((Bool) -> Void)?

    private(set) var lastTrack: Track?

    // MARK: - 內部(SDK 存在時才有意義)

    #if canImport(SpotifyiOS)
    private var appRemote: SPTAppRemote?
    private var lastPlayerState: (position: TimeInterval, speed: Double, isPaused: Bool, hostTime: Double)?
    #else
    private var lastPlayerState: (position: TimeInterval, speed: Double, isPaused: Bool, hostTime: Double)?
    #endif

    private var isrcTask: Task<Void, Never>?

    // MARK: - 連線

    /// 建立 App Remote 並啟動授權流程(會開啟 Spotify App)。
    func connect(clientID: String) {
        #if canImport(SpotifyiOS)
        guard !clientID.trimmed.isEmpty else {
            connectionErrorMessage = "請先在設定中填入 Spotify Client ID"
            return
        }
        connectionErrorMessage = nil
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: AppConstants.spotifyRedirectURL)
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        remote.delegate = self
        appRemote = remote
        connectionState = .connecting
        // 空字串 = 授權後沿用 Spotify 最後播放內容,不強制插播
        remote.authorizeAndPlayURI("") { [weak self] success in
            Task { @MainActor in
                if !success {
                    self?.connectionState = .failed
                    self?.connectionErrorMessage = "Spotify 未安裝或無法啟動授權流程"
                }
            }
        }
        #else
        connectionState = .failed
        connectionErrorMessage = "專案尚未加入 SpotifyiOS SDK(見設定頁說明)"
        #endif
    }

    /// 處理 Spotify 授權回跳 URL(由 App 的 onOpenURL 轉發)。
    /// 回傳 true 表示此 URL 屬於 Spotify 回呼。
    ///
    /// [稽核 F2 修補] 縱深防禦:
    /// 1. 僅在「我們主動發起的授權流程」(state == .connecting)期間接受 callback,
    ///    阻斷惡意 App 任意時刻偽造 `lyricflow://` 連結注入 token / 錯誤訊息。
    /// 2. 驗證 scheme 與 host(custom scheme 在 iOS 可被同機 App 搶註冊,
    ///    host + state 檢查無法完全根除此風險,但可關閉最容易的攻擊路徑)。
    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        #if canImport(SpotifyiOS)
        guard let remote = appRemote,
              connectionState == .connecting,
              url.scheme == AppConstants.spotifyRedirectScheme,
              url.host == AppConstants.spotifyRedirectURL.host,
              let parameters = remote.authorizationParameters(from: url)
        else { return false }

        if let error = parameters[SPTAppRemoteErrorDescriptionKey] {
            connectionState = .failed
            connectionErrorMessage = "授權失敗:\(error)"
            return true
        }
        if let token = parameters[SPTAppRemoteAccessTokenKey] {
            remote.connectionParameters.accessToken = token
            // [自動連線] 保存權杖到 Keychain(短期效期;有效期間啟動 App 可靜默連線)
            let expiresIn = Self.expiresIn(from: url)
            KeychainStore.save(token, forKey: Self.tokenKeychainKey)
            KeychainStore.save(
                String(Date().addingTimeInterval(expiresIn - 60).timeIntervalSince1970),
                forKey: Self.tokenExpiryKeychainKey
            )
            connectionState = .connecting
            remote.connect()
            return true
        }
        #endif
        return false
    }

    func disconnect() {
        #if canImport(SpotifyiOS)
        appRemote?.playerAPI?.delegate = nil
        appRemote?.disconnect()
        #endif
        // [自動連線] 主動斷線時同步清除快取權杖
        KeychainStore.delete(forKey: Self.tokenKeychainKey)
        KeychainStore.delete(forKey: Self.tokenExpiryKeychainKey)
        connectionState = .disconnected
        lastPlayerState = nil
        lastTrack = nil
        onTrackChange?(nil)
    }

    // MARK: - 自動連線(Spotify 權杖快取)

    private static let tokenKeychainKey = "spotifyAccessToken"
    private static let tokenExpiryKeychainKey = "spotifyTokenExpiry"

    /// 啟動/回前景時自動連線:
    /// 1. 同一次執行內已有 in-memory 權杖 → 直接重連
    /// 2. Keychain 快取權杖未過期 → 靜默連線(不跳 Spotify App)
    /// 權杖過期後不自動跳轉重新授權 —— authorizeAndPlayURI 會自動播放
    /// 上一首歌,打斷使用者正在聽的內容,故保留手動一鍵重連。
    func autoConnect(clientID: String) {
        #if canImport(SpotifyiOS)
        guard connectionState == .disconnected || connectionState == .failed else { return }
        guard !clientID.trimmed.isEmpty else { return }

        // 1) in-memory 權杖(前景恢復)
        if let remote = appRemote, !remote.isConnected,
           !(remote.connectionParameters.accessToken ?? "").isEmpty {
            connectionState = .connecting
            remote.connect()
            return
        }

        // 2) Keychain 快取權杖
        guard Self.cachedToken() != nil else { return }

        if appRemote == nil {
            let configuration = SPTConfiguration(clientID: clientID, redirectURL: AppConstants.spotifyRedirectURL)
            let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
            remote.delegate = self
            appRemote = remote
        }
        appRemote?.connectionParameters.accessToken = Self.cachedToken()
        connectionState = .connecting
        appRemote?.connect()
        #endif
    }

    /// 取得未過期的快取權杖(過期或無 → nil)。
    private static func cachedToken() -> String? {
        guard let token = KeychainStore.load(Self.tokenKeychainKey),
              !token.isEmpty,
              let expiryRaw = KeychainStore.load(Self.tokenExpiryKeychainKey),
              let expiry = Double(expiryRaw),
              expiry > Date().timeIntervalSince1970
        else { return nil }
        return token
    }

    /// 從回呼 URL 解析 expires_in(秒);無則預設 3600。
    private static func expiresIn(from url: URL) -> TimeInterval {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "expires_in" })?.value,
              let seconds = TimeInterval(raw)
        else { return 3600 }
        return seconds
    }

    /// 快取權杖是否仍有效(供設定頁顯示提示)。
    var hasValidCachedToken: Bool {
        Self.cachedToken() != nil
    }

    // MARK: - 播放狀態讀取

    /// 依 lastPlayerState 內插計算目前播放位置(秒)。
    var playbackPosition: TimeInterval? {
        guard let state = lastPlayerState else { return nil }
        if state.isPaused { return state.position / 1000 }
        let elapsed = (CACurrentMediaTime() - state.hostTime) * state.speed
        return (state.position + elapsed * 1000) / 1000
    }

    var isPlaying: Bool {
        lastPlayerState.map { !$0.isPaused } ?? false
    }

    // MARK: - 播放控制

    func play() {
        #if canImport(SpotifyiOS)
        appRemote?.playerAPI?.resume(nil)
        #endif
    }

    func pause() {
        #if canImport(SpotifyiOS)
        appRemote?.playerAPI?.pause(nil)
        #endif
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    func next() {
        #if canImport(SpotifyiOS)
        // SDK 將 skipToNext: 匯入為 skip(toNext:)
        appRemote?.playerAPI?.skip(toNext: nil)
        #endif
    }

    func previous() {
        #if canImport(SpotifyiOS)
        appRemote?.playerAPI?.skip(toPrevious: nil)
        #endif
    }

    func seek(to position: TimeInterval) {
        #if canImport(SpotifyiOS)
        appRemote?.playerAPI?.seek(toPosition: Int(position * 1000), callback: nil)
        #endif
    }

    // MARK: - SDK 事件

    #if canImport(SpotifyiOS)
    private func handlePlayerState(_ state: any SPTAppRemotePlayerState) {
        lastPlayerState = (
            position: TimeInterval(state.playbackPosition),
            speed: Double(state.playbackSpeed),
            isPaused: state.isPaused,
            hostTime: CACurrentMediaTime()
        )

        let track = makeTrack(from: state.track)
        let trackChanged = track?.id != lastTrack?.id
        lastTrack = track
        if trackChanged {
            onTrackChange?(track)
            fetchArtwork(for: state.track, trackID: track?.id)
        }
        onPlaybackStateChange?(!state.isPaused)
    }

    private func makeTrack(from stateTrack: (any SPTAppRemoteTrack)?) -> Track? {
        // SDK 標頭以 NS_ASSUME_NONNULL 宣告:name / artist / album 皆為非選填
        guard let stateTrack, !stateTrack.name.isEmpty, !stateTrack.isAdvertisement else { return nil }
        let artist = stateTrack.artist.name
        let album = stateTrack.album.name
        let track = Track(
            id: Track.makeID(title: stateTrack.name, artist: artist, source: .spotify),
            title: stateTrack.name,
            artist: artist,
            album: album,
            duration: TimeInterval(stateTrack.duration) / 1000,
            source: .spotify,
            spotifyURI: stateTrack.uri
        )
        return track
    }

    private func fetchArtwork(for _: any SPTAppRemoteTrack, trackID _: String?) {
        // [v1 範圍決策] SDK 的 fetchImage Swift 橋接形式不穩定(async 版回傳 Void,
        // 影像無法取得),為保證建置通過先停用 Spotify 封面下載 ——
        // UI 會顯示漸層預設圖,不影響歌詞/翻譯/控制功能。
        // TODO: 拿到 SDK 實際 Swift 介面後,以 callback 形式補回。
    }
    #endif
}

// MARK: - SPTAppRemoteDelegate

#if canImport(SpotifyiOS)
extension SpotifyService: SPTAppRemoteDelegate {

    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.connectionState = .connected
            self.connectionErrorMessage = nil
            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: nil)
            appRemote.playerAPI?.getPlayerState { [weak self] result, _ in
                guard let state = result as? (any SPTAppRemotePlayerState) else { return }
                Task { @MainActor in
                    self?.handlePlayerStatePrivate(state)
                }
            }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            self.connectionState = .failed
            self.connectionErrorMessage = error?.localizedDescription ?? "無法連線 Spotify App"
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            self.connectionState = .disconnected
            self.lastPlayerState = nil
        }
    }

    /// getPlayerState 回呼與 delegate 都會走這裡,集中處理。
    private func handlePlayerStatePrivate(_ state: any SPTAppRemotePlayerState) {
        handlePlayerState(state)
    }
}

extension SpotifyService: SPTAppRemotePlayerStateDelegate {

    nonisolated func playerStateDidChange(_ playerState: any SPTAppRemotePlayerState) {
        Task { @MainActor in
            self.handlePlayerStatePrivate(playerState)
        }
    }
}
#endif
