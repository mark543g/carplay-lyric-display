import Foundation

/// 網易雲音樂歌詞來源(免金鑰,Musixmatch 改為付費後的替代方案之一)。
///
/// - 華語/日韓歌曲覆蓋率高,並隨附**官方翻譯歌詞(tlyric)** ——
///   可直接填入雙語顯示,無需 Apple Translation
/// - 使用網易雲公開端點(非官方 API,社群工具普遍採用;可能受區域或限流影響)
/// - 流程:搜尋取 songID(以時長挑最接近者)→ 取 lrc + tlyric
struct NetEaseProvider {

    private let searchURL = URL(string: "https://music.163.com/api/search/get")!
    private let lyricURL = URL(string: "https://music.163.com/api/song/lyric")!
    /// 時長可容許誤差(秒)
    private let durationTolerance: TimeInterval = 10
    /// [稽核 F5] 歌詞原文長度上限(512KB)
    private static let maxLyricsBytes = 512 * 1024

    enum ProviderError: Error {
        case noMatch
        case badResponse
    }

    func findLyrics(for track: Track) async throws -> LyricsDocument? {
        guard let songID = try await searchSongID(for: track) else { return nil }
        return try await fetchLyrics(songID: songID, track: track)
    }

    // MARK: - 搜尋 songID

    private func searchSongID(for track: Track) async throws -> Int? {
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "s", value: "\(track.title) \(track.artist)"),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components.url else { throw ProviderError.badResponse }

        let data = try await request(url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]],
              !songs.isEmpty
        else { return nil }

        // 挑選:優先時長最接近者;完全無時長資訊時取第一筆(搜尋相關性排序已足夠)
        var bestID: Int?
        var bestDelta = TimeInterval.greatestFiniteMagnitude
        for song in songs {
            guard let id = (song["id"] as? NSNumber)?.intValue else { continue }
            if let ms = (song["duration"] as? NSNumber)?.doubleValue, track.duration > 0 {
                let delta = abs(ms / 1000 - track.duration)
                if delta < bestDelta {
                    bestDelta = delta
                    bestID = id
                }
            } else if bestID == nil {
                bestID = id
            }
        }
        return bestID
    }

    // MARK: - 取歌詞 lrc + tlyric

    private func fetchLyrics(songID: Int, track: Track) async throws -> LyricsDocument? {
        var components = URLComponents(url: lyricURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "1"),
            URLQueryItem(name: "tv", value: "-1"),
        ]
        guard let url = components.url else { throw ProviderError.badResponse }

        let data = try await request(url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lrcObj = root["lrc"] as? [String: Any],
              let lrcText = lrcObj["lyric"] as? String,
              !lrcText.isEmpty,
              lrcText.count <= Self.maxLyricsBytes
        else { return nil }

        let parsed = LRCParser.parse(lrcText)
        guard !parsed.lines.isEmpty else { return nil }

        var document = LyricsDocument(trackID: track.id, provider: "網易雲", isSynced: true, lines: parsed.lines)

        // 官方翻譯歌詞(tlyric):時間戳與原文一致 → 以時間對位填入
        if let tObj = root["tlyric"] as? [String: Any],
           let tText = tObj["lyric"] as? String,
           !tText.isEmpty,
           tText.count <= Self.maxLyricsBytes {
            let tParsed = LRCParser.parse(tText)
            var map: [String: String] = [:]
            for line in tParsed.lines where !line.text.isEmpty {
                map[Self.timeKey(line.startTime)] = line.text
            }
            for line in document.lines {
                if let translation = map[Self.timeKey(line.startTime)] {
                    document.translations[line.index] = translation
                }
            }
        }
        return document
    }

    private static func timeKey(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds)
    }

    // MARK: - 請求

    private func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LyricFlow/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ProviderError.badResponse
        }
        return data
    }
}
