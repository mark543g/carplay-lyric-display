import Foundation
import MediaPlayer
import MusicKit
import UIKit
import QuartzCore

/// Apple Music(Music App)播放監聽與控制。
///
/// 使用 `MPMusicPlayerController.systemMusicPlayer` 鏡像 Music App 的播放狀態:
/// - `nowPlayingItemDidChangeNotification` / `playbackStateDidChangeNotification` 感測換歌與播放暫停
/// - `currentPlaybackTime` 輪詢取得即時播放位置(亦可用賦值 seek)
/// - 透過 MusicKit 目錄搜尋解析 ISRC,提高 Musixmatch 歌詞比對精準度
@MainActor
final class AppleMusicService: NSObject {

    static let shared = AppleMusicService()

    private let player: MPMusicPlayerController = .systemMusicPlayer
    private var observers: [NSObjectProtocol] = []
    private var isrcTask: Task<Void, Never>?

    /// 換歌 / 播放狀態改變時回呼(主執行緒)。
    var onTrackChange: ((Track?) -> Void)?
    var onPlaybackStateChange: ((Bool) -> Void)?

    private(set) var lastTrack: Track?

    func startMonitoring() {
        guard observers.isEmpty else { return }
        player.beginGeneratingPlaybackNotifications()

        let center = NotificationCenter.default
        // 注意:通知常數以 NSNotification.Name 成員形式匯入(去掉 Notification 字尾)
        observers.append(center.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleItemChange()
            }
        })
        observers.append(center.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleStateChange()
            }
        })
        handleItemChange()
        handleStateChange()
    }

    func stopMonitoring() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        isrcTask?.cancel()
        player.endGeneratingPlaybackNotifications()
    }

    // MARK: - 播放狀態讀取

    /// [背景凍結修正] `currentPlaybackTime` 在 App 進背景後會回傳靜止值,
    /// 導致背景永遠偵測不到歌詞換行(即時活動/小工具隨之凍結)。
    /// 改採與 SpotifyService 相同的「錨點 + 經過時間」內插:
    /// 系統回報的位置「有在動」時重新校正錨點;凍結時自行推算。
    /// 背景可信播放狀態:前景用系統即時值;背景系統值可能失真/凍結,
    /// 改用狀態通知最後確認的值(通知未送達時維持進入背景時的狀態)。
    private var lastKnownPlaying = false
    /// 剛從播放轉停(僅轉換瞬間允許凍結錨點一次)。
    private var wasTrustedPlaying = false
    private var anchorPosition: TimeInterval = 0
    private var anchorHostTime: CFTimeInterval = 0
    private var lastLiveReading: TimeInterval = -1
    /// 目前曲目時長(換行推算超出時夾住,避免跨到下一首)。
    private var currentDuration: TimeInterval = 0

    /// 目前播放位置(秒)。
    var playbackPosition: TimeInterval {
        let live = player.currentPlaybackTime
        let now = CACurrentMediaTime()

        if trustedPlaying {
            wasTrustedPlaying = true
            // 系統回報值有變化(前景)→ 校正錨點;凍結(背景)→ 沿用舊錨點自行推算
            if abs(live - lastLiveReading) > 0.05 {
                anchorPosition = live
                anchorHostTime = now
            }
            lastLiveReading = live
            let deadReckoned = anchorPosition + (now - anchorHostTime)
            return currentDuration > 0 ? min(deadReckoned, currentDuration) : deadReckoned
        } else {
            // 暫停:以系統值為準並重設錨點
            if wasTrustedPlaying {
                // 剛轉停:前景採系統值;背景採「推算到此刻」後凍結(背景系統值凍結不可信)
                anchorPosition = UIApplication.shared.applicationState == .active
                    ? live
                    : anchorPosition + (now - anchorHostTime)
                anchorHostTime = now
                lastLiveReading = live
                wasTrustedPlaying = false
            } else if anchorHostTime == 0 {
                // 從未建立錨點(啟動時即暫停):直接採用系統值
                anchorPosition = live
                anchorHostTime = now
                lastLiveReading = live
            }
            return currentDuration > 0 ? min(anchorPosition, currentDuration) : anchorPosition
        }
    }

    var isPlaying: Bool { trustedPlaying }

    /// 播放狀態:前景 = 系統即時值;背景 = 通知確認值(避免背景凍結/誤報讓位置停走)。
    private var trustedPlaying: Bool {
        UIApplication.shared.applicationState == .active
            ? player.playbackState == .playing
            : lastKnownPlaying
    }

    // MARK: - 播放控制(MPMediaPlayback)

    func play() { player.play() }
    func pause() { player.pause() }
    func togglePlayPause() { isPlaying ? pause() : play() }
    func next() { player.skipToNextItem() }
    func previous() { player.skipToPreviousItem() }

    /// Seek 到指定秒數(透過 MPMediaPlayback.currentPlaybackTime 賦值)。
    func seek(to position: TimeInterval) {
        player.currentPlaybackTime = max(0, position)
    }

    // MARK: - 內部處理

    private func handleItemChange() {
        let track = makeTrack(from: player.nowPlayingItem)
        currentDuration = track?.duration ?? 0
        lastLiveReading = -1 // 換歌:強制下次輪詢重新校正錨點
        // 沿用同一首則不觸發換歌
        if let new = track, let old = lastTrack, new.id == old.id, new.title == old.title {
            lastTrack = track
            return
        }
        lastTrack = track
        onTrackChange?(track)
        enrichISRC(for: track)
    }

    private func handleStateChange() {
        lastKnownPlaying = player.playbackState == .playing
        lastLiveReading = -1 // 播放/暫停轉換:重新校正錨點
        onPlaybackStateChange?(isPlaying)
    }

    private func makeTrack(from item: MPMediaItem?) -> Track? {
        guard let item,
              let title = item.value(forProperty: MPMediaItemPropertyTitle) as? String,
              !title.isEmpty
        else { return nil }

        let artist = (item.value(forProperty: MPMediaItemPropertyArtist) as? String) ?? "未知歌手"
        let album = item.value(forProperty: MPMediaItemPropertyAlbumTitle) as? String
        let duration = (item.value(forProperty: MPMediaItemPropertyPlaybackDuration) as? NSNumber)?.doubleValue ?? 0

        var artworkPNG: Data?
        if let artwork = item.value(forProperty: MPMediaItemPropertyArtwork) as? MPMediaItemArtwork,
           let image = artwork.image(at: CGSize(width: 256, height: 256)) {
            artworkPNG = image.pngData()
        }

        return Track(
            id: Track.makeID(title: title, artist: artist, source: .appleMusic),
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            source: .appleMusic,
            artworkPNG: artworkPNG
        )
    }

    /// 透過 MusicKit 目錄查詢 ISRC(非必要,失敗不影響歌詞比對)。
    private func enrichISRC(for track: Track?) {
        guard let track else { return }
        isrcTask?.cancel()
        isrcTask = Task { [weak self] in
            guard let isrc = await self?.resolveISRC(for: track), !Task.isCancelled else { return }
            // 僅在仍是同一首歌時套用(Track 為 struct,需以 var 取出修改)
            guard var current = self?.lastTrack, current.id == track.id else { return }
            current.isrc = isrc
            self?.lastTrack = current
            self?.onTrackChange?(current)
        }
    }

    private func resolveISRC(for track: Track) async -> String? {
        let status = await MusicAuthorization.request()
        guard status == .authorized else { return nil }
        do {
            var request = MusicCatalogSearchRequest(term: "\(track.title) \(track.artist)", types: [Song.self])
            request.limit = 8
            let response = try await request.response()
            let songs = response.songs
            // 先以歌手名稱過濾,再取時長最接近者
            let candidates = songs.filter { song in
                song.artistName.localizedCaseInsensitiveContains(track.artist)
                || track.artist.localizedCaseInsensitiveContains(song.artistName)
            }
            let pool = candidates.isEmpty ? Array(songs) : candidates
            let best = pool
                .sorted { lhs, rhs in
                    let l = abs((lhs.duration ?? 0) - track.duration)
                    let r = abs((rhs.duration ?? 0) - track.duration)
                    return l < r
                }
                .first
            return best?.isrc
        } catch {
            return nil
        }
    }
}
