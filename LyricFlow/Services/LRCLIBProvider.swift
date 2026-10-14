import Foundation

/// LRCLIB 歌詞提供者(免費、開源、免 API Key,作為 Musixmatch 的回退來源)。
///
/// API 文件:https://lrclib.net/docs
/// - `GET /api/get?artist_name=&track_name=&album_name=&duration=` → 精確查詢(404 表示找不到)
/// - `GET /api/search?track_name=&artist_name=` → 模糊搜尋,回傳陣列後自行以時長比對
struct LRCLIBProvider {

    private let baseURL = URL(string: "https://lrclib.net/api")!
    /// 時長可容許誤差(秒)
    private let durationTolerance: TimeInterval = 8
    /// [稽核 F5 修補] 第三方歌詞原文長度上限(512KB),防惡意回應造成記憶體/CPU 耗盡。
    private static let maxLyricsBytes = 512 * 1024

    enum ProviderError: Error {
        case noMatch
        case badResponse
    }

    func findLyrics(for track: Track) async throws -> LyricsDocument {
        // 1) 精確查詢
        if let document = try? await exactGet(track: track) {
            return document
        }
        // 2) 模糊搜尋 + 時長比對
        if let document = try await searchFallback(track: track) {
            return document
        }
        throw ProviderError.noMatch
    }

    // MARK: - /api/get

    private struct LRCLIBHit: Decodable {
        let trackName: String
        let artistName: String
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private func exactGet(track: Track) async throws -> LyricsDocument? {
        var components = URLComponents(url: baseURL.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if let album = track.album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if track.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        }
        components.queryItems = items
        guard let url = components.url else { throw ProviderError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LyricFlow/1.0 (iOS; https://github.com/lab/lyricflow)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let hit = try? JSONDecoder().decode(LRCLIBHit.self, from: data)
        else { return nil }
        return document(from: hit, trackID: track.id)
    }

    // MARK: - /api/search

    private func searchFallback(track: Track) async throws -> LyricsDocument? {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        guard let url = components.url else { throw ProviderError.badResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LyricFlow/1.0 (iOS; https://github.com/lab/lyricflow)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let hits = try? JSONDecoder().decode([LRCLIBHit].self, from: data),
              !hits.isEmpty
        else { return nil }

        // 依「有同步歌詞」與「時長接近度」排序
        let ranked = hits
            .filter { hit in
                if let instrumental = hit.instrumental, instrumental { return false }
                return true
            }
            .sorted { lhs, rhs in
                let lhsSynced = (lhs.syncedLyrics?.isEmpty == false)
                let rhsSynced = (rhs.syncedLyrics?.isEmpty == false)
                if lhsSynced != rhsSynced { return lhsSynced }
                let l = abs((lhs.duration ?? 0) - track.duration)
                let r = abs((rhs.duration ?? 0) - track.duration)
                return l < r
            }

        for hit in ranked {
            if let document = document(from: hit, trackID: track.id) {
                // 時長差距過大則不採用
                if let duration = hit.duration, track.duration > 0,
                   abs(duration - track.duration) > durationTolerance {
                    continue
                }
                return document
            }
        }
        return nil
    }

    // MARK: - 轉換

    private func document(from hit: LRCLIBHit, trackID: String) -> LyricsDocument? {
        if let synced = hit.syncedLyrics, !synced.isEmpty, synced.count <= Self.maxLyricsBytes {
            let parsed = LRCParser.parse(synced)
            guard !parsed.lines.isEmpty else { return nil }
            return LyricsDocument(trackID: trackID, provider: "LRCLIB", isSynced: true, lines: parsed.lines)
        }
        if let plain = hit.plainLyrics, !plain.isEmpty, plain.count <= Self.maxLyricsBytes {
            let paragraphs = plain
                .components(separatedBy: .newlines)
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
            guard !paragraphs.isEmpty else { return nil }
            let entries: [(time: TimeInterval, text: String)] = paragraphs.enumerated().map { index, text in
                (TimeInterval(index) * 5, text)
            }
            return LyricsDocument(
                trackID: trackID,
                provider: "LRCLIB",
                isSynced: false,
                lines: MusixmatchProvider.buildLines(from: entries)
            )
        }
        return nil
    }
}
