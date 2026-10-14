import Foundation
import WidgetKit

/// 把「目前播放 + 整首歌詞時間軸」寫入 App Group,並觸發 Widget 重建 Timeline。
///
/// Widget 一次 Timeline 請求就涵蓋整首歌(逐行條目),
/// 因此只在「結構性變化」時呼叫 reload(換歌、歌詞載入、暫停/播放、seek),
/// 不需在每行歌詞推進時 reload → 不受系統刷新預算限制。
@MainActor
enum SharedSnapshotWriter {

    static func write(
        track: Track?,
        lyrics: LyricsDocument?,
        position: TimeInterval,
        isPlaying: Bool,
        lineIndex: Int?
    ) {
        guard let track else {
            SharedStore.saveSnapshot(
                NowPlayingSnapshot(
                    trackID: "",
                    title: "未播放",
                    artist: "—",
                    source: MusicSource.appleMusic.rawValue,
                    isPlaying: false,
                    duration: 0,
                    hasSyncedLyrics: false,
                    lines: [],
                    position: 0
                )
            )
            return
        }

        let lines: [LyricsLineSnapshot]
        var synced = false
        if let lyrics {
            synced = lyrics.isSynced
            lines = lyrics.snapshotLines(translations: true)
        } else {
            lines = []
        }

        let snapshot = NowPlayingSnapshot(
            trackID: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            source: track.source.rawValue,
            isPlaying: isPlaying,
            duration: track.duration,
            artworkPNG: track.artworkPNG,
            provider: lyrics?.provider,
            hasSyncedLyrics: synced,
            lines: lines,
            position: position,
            lineIndex: lineIndex
        )
        SharedStore.saveSnapshot(snapshot)
    }

    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
