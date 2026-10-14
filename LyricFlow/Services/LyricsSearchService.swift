import Foundation

/// 歌詞搜尋總管:Musixmatch(優先)→ LRCLIB(回退),附標題清潔與快取。
@MainActor
final class LyricsSearchService {

    static let shared = LyricsSearchService()

    enum SearchState: Equatable {
        case idle
        case loading
        case loaded(provider: String)
        case notFound
        case failed(String)
    }

    /// 記憶體快取(trackID → 文件),避免同首歌重複查詢。
    private var memoryCache: [String: LyricsDocument] = [:]
    /// 進行中的查詢,換歌快速連跳時自動丟棄舊結果。
    private var searchTask: Task<LyricsDocument?, Never>?

    func cachedDocument(for trackID: String) -> LyricsDocument? {
        memoryCache[trackID]
    }

    func invalidateCache(for trackID: String? = nil) {
        if let trackID {
            memoryCache.removeValue(forKey: trackID)
        } else {
            memoryCache.removeAll()
        }
    }

    /// 主流程:搜尋歌詞。回傳 nil 表示所有來源都找不到。
    func searchLyrics(for track: Track, musixmatchKey: String?, forceRefresh: Bool = false) async -> LyricsDocument? {
        if !forceRefresh, let cached = memoryCache[track.id] {
            return cached
        }

        searchTask?.cancel()
        let task = Task<LyricsDocument?, Never> { [weak self] in
            guard let self else { return nil }

            // 1) Musixmatch(有 Key 才嘗試)
            if let key = musixmatchKey, !key.trimmed.isEmpty {
                let musixmatch = MusixmatchProvider(apiKey: key)
                if let document = try? await musixmatch.findLyrics(for: track) {
                    if Task.isCancelled { return nil }
                    self.memoryCache[track.id] = document
                    return document
                }
            }

            // 2) LRCLIB
            let lrclib = LRCLIBProvider()
            if let document = try? await lrclib.findLyrics(for: track) {
                if Task.isCancelled { return nil }
                self.memoryCache[track.id] = document
                return document
            }

            // 3) 以清潔後的標題重試一次(去除「(Official Video)」等雜訊)
            let cleanedTrack = Self.cleaned(track)
            if cleanedTrack.id != track.id {
                if let document = try? await lrclib.findLyrics(for: cleanedTrack) {
                    if Task.isCancelled { return nil }
                    self.memoryCache[track.id] = document
                    return document
                }
            }

            return nil
        }
        searchTask = task
        let result = await task.value
        searchTask = nil
        return result
    }

    /// 清除標題中的常見雜訊,提升歌詞庫比對成功率。
    static func cleaned(_ track: Track) -> Track {
        var cleaned = track
        cleaned.title = track.title
        var title = track.title

        // 移除括號雜訊:(Official Music Video)、(Lyrics)、[4K] …
        let bracketNoise = [
            "(official video)", "(official music video)", "(official audio)", "(official visualizer)",
            "(lyric video)", "(lyrics)", "(audio)", "(visualizer)", "(hd)", "(hq)", "(4k)", "(mv)",
        ]
        for noise in bracketNoise {
            title = title.replacingOccurrences(of: noise, with: "", options: .caseInsensitive)
        }
        // 移除方括號內容
        title = title.replacingOccurrences(
            of: #"\[[^\]]*\]"#,
            with: "",
            options: .regularExpression
        )
        // 移除尾端 "- Live at ..." 等變體標記
        title = title.replacingOccurrences(
            of: #"\s*[-–—]\s*(live|remaster(ed)?( \d{4})?|single version|radio edit).*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // 「feat.」之後的特別來賓
        title = title.replacingOccurrences(
            of: #"\s*(feat\.?|ft\.?|featuring).*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        cleaned.title = title.trimmed.isEmpty ? track.title : title.trimmed

        // 歌手同名清理
        var artist = track.artist
        artist = artist.replacingOccurrences(
            of: #"\s*[-–—]\s*Topic.*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        if let separator = artist.range(of: #",|;| feat\.| ft\.| featuring\.?"#, options: .regularExpression) {
            artist = String(artist[..<separator.lowerBound])
        }
        cleaned.artist = artist.trimmed.isEmpty ? track.artist : artist.trimmed
        cleaned.id = Track.makeID(title: cleaned.title, artist: cleaned.artist, source: track.source)
        return cleaned
    }
}
