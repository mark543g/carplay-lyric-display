import Foundation
import MediaPlayer
import MusicKit
import UIKit

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
        observers.append(center.addObserver(
            forName: MPMusicPlayerController.nowPlayingItemDidChangeNotification,
            object: player, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleItemChange()
            }
        })
        observers.append(center.addObserver(
            forName: MPMusicPlayerController.playbackStateDidChangeNotification,
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

    /// 目前播放位置(秒)。
    var playbackPosition: TimeInterval {
        player.currentPlaybackTime
    }

    var isPlaying: Bool {
        player.playbackState == .playing
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
            // 僅在仍是同一首歌時套用
            guard let current = self?.lastTrack, current.id == track.id else { return }
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
