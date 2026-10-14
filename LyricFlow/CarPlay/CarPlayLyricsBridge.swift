import Foundation

/// CarPlay 場景與主 App 之間的橋接器。
///
/// PlaybackCenter 不直接持有 CarPlay scene delegate(生命週期由系統管理),
/// 透過此單例轉發換歌 / 換行 / 播放狀態變化。
@MainActor
final class CarPlayLyricsBridge {

    static let shared = CarPlayLyricsBridge()

    weak var sceneDelegate: CarPlaySceneDelegate?

    // 目前狀態(scene 連上時用於立即同步)
    private(set) var currentTrack: Track?
    private(set) var currentLyrics: LyricsDocument?
    private(set) var currentLineIndex: Int?
    private(set) var currentTranslation: String?
    private(set) var isPlaying = false

    func trackChanged(track: Track?, lyrics: LyricsDocument?) {
        currentTrack = track
        currentLyrics = lyrics
        currentLineIndex = nil
        currentTranslation = nil
        sceneDelegate?.rebuildForTrack(track: track, lyrics: lyrics)
    }

    func lineChanged(index: Int?, text: String?, translation: String?, nextText: String?) {
        currentLineIndex = index
        currentTranslation = translation
        sceneDelegate?.updateLines(index: index,
                                    text: text,
                                    translation: translation,
                                    nextText: nextText,
                                    lyrics: currentLyrics)
    }

    func playbackStateChanged(isPlaying: Bool) {
        self.isPlaying = isPlaying
        sceneDelegate?.updatePlaybackState(isPlaying: isPlaying)
    }
}
