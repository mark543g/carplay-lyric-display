import Foundation

/// Musixmatch 歌詞提供者(優先來源)。
///
/// 流程:
/// 1. `matcher.track.get` 以 ISRC(若有)或歌名/歌手取得曲目 metadata(track_length、commontrack_id)
/// 2. `track.subtitle.get` 取得時間同步歌詞(JSON)
/// 3. 同步歌詞失敗時退回 `track.lyrics.get` 取純文字歌詞
///
/// 需要 API Key:https://developer.musixmatch.com(設定頁填入)。
struct MusixmatchProvider {

    struct TrackMeta {
        var commontrackID: Int
        var trackLength: TimeInterval?
        var trackID: Int
    }

    let apiKey: String?
    private let baseURL = URL(string: "https://apiclient.musixmatch.com/ws/1.1")!

    /// [稽核 F5 修補] 第三方歌詞原文長度上限(512KB),防惡意回應造成記憶體/CPU 耗盡。
    static let maxLyricsBytes = 512 * 1024

    var isAvailable: Bool {
        guard let key = apiKey, !key.trimmed.isEmpty else { return false }
        return true
    }

    enum ProviderError: Error {
        case missingKey
        case noMatch
        case badResponse
    }

    func findLyrics(for track: Track) async throws -> LyricsDocument {
        guard isAvailable, let key = apiKey else { throw ProviderError.missingKey }

        // 1) 查曲目 metadata
        var metaQueryItems: [URLQueryItem] = [
            URLQueryItem(name: "apikey", value: key),
            URLQueryItem(name: "f_has_lyrics", value: "1"),
        ]
        if let isrc = track.isrc, !isrc.isEmpty {
            metaQueryItems.append(URLQueryItem(name: "track_isrc", value: isrc))
        }
        metaQueryItems.append(URLQueryItem(name: "q_track", value: track.title))
        metaQueryItems.append(URLQueryItem(name: "q_artist", value: track.artist))

        let meta = try await fetchTrackMeta(queryItems: metaQueryItems, expectedDuration: track.duration)
        guard let meta else { throw ProviderError.noMatch }

        // 2) 同步歌詞(subtitle)
        if let synced = try? await fetchSubtitle(commontrackID: meta.commontrackID, trackID: track.id, apiKey: key) {
            return synced
        }

        // 3) 純文字歌詞
        if let plain = try? await fetchPlainLyrics(commontrackID: meta.commontrackID, trackID: track.id, apiKey: key) {
            return plain
        }

        throw ProviderError.noMatch
    }

    // MARK: - matcher.track.get

    private func fetchTrackMeta(queryItems: [URLQueryItem], expectedDuration: TimeInterval) async throws -> TrackMeta? {
        let data = try await request(path: "matcher.track.get", queryItems: queryItems)
        guard let body = Self.messageBody(from: data),
              let trackDict = Self.value(in: body, forKey: "track") as? [String: Any]
        else { throw ProviderError.badResponse }

        guard let commontrackID = Self.intValue(trackDict["commontrack_id"]),
              let trackID = Self.intValue(trackDict["track_id"])
        else { return nil }

        var length: TimeInterval?
        if let raw = trackDict["track_length"] {
            length = Self.doubleValue(raw)
        }

        // 若 API 回傳時長且與本機差異過大(>15 秒),視為錯誤比對
        if let length, expectedDuration > 0, abs(length - expectedDuration) > 15 {
            // 嘗試再找候選比對太複雜,此處直接退回交由 LRCLIB
            return nil
        }
        return TrackMeta(commontrackID: commontrackID, trackLength: length, trackID: trackID)
    }

    // MARK: - 同步歌詞 track.subtitle.get

    private func fetchSubtitle(commontrackID: Int, trackID: String, apiKey: String) async throws -> LyricsDocument {
        let data = try await request(path: "track.subtitle.get", queryItems: [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "commontrack_id", value: String(commontrackID)),
        ])
        guard let body = Self.messageBody(from: data),
              let subtitleDict = Self.value(in: body, forKey: "subtitle") as? [String: Any],
              let subtitleBody = subtitleDict["subtitle_body"] as? String,
              subtitleBody.count <= Self.maxLyricsBytes,
              let subtitleData = subtitleBody.data(using: .utf8),
              let rawLines = try? JSONSerialization.jsonObject(with: subtitleData) as? [[String: Any]]
        else { throw ProviderError.badResponse }

        var entries: [(time: TimeInterval, text: String)] = []
        for raw in rawLines {
            // 防禦性解析:不同版本欄位名稱略有差異
            var seconds: Double = 0
            if let sec = Self.doubleValue(raw["seconds"]) { seconds = sec }
            else if let ms = Self.doubleValue(raw["milliseconds"]) { seconds = ms / 1000 }
            var minutes: Double = 0
            if let min = Self.doubleValue(raw["minutes"]) { minutes = min }
            let text = (raw["text"] as? String) ?? (raw["line"] as? String) ?? ""
            let time = minutes * 60 + seconds
            if !text.isEmpty, time >= 0 {
                entries.append((time, text.trimmed))
            }
        }
        guard !entries.isEmpty else { throw ProviderError.badResponse }
        entries.sort { $0.time < $1.time }

        let lines = Self.buildLines(from: entries)
        return LyricsDocument(
            trackID: trackID,
            provider: "Musixmatch",
            isSynced: true,
            lines: lines
        )
    }

    // MARK: - 純文字歌詞 track.lyrics.get

    private func fetchPlainLyrics(commontrackID: Int, trackID: String, apiKey: String) async throws -> LyricsDocument {
        let data = try await request(path: "track.lyrics.get", queryItems: [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "commontrack_id", value: String(commontrackID)),
        ])
        guard let body = Self.messageBody(from: data),
              let lyricsDict = Self.value(in: body, forKey: "lyrics") as? [String: Any],
              let lyricsBody = lyricsDict["lyrics_body"] as? String,
              lyricsBody.count <= Self.maxLyricsBytes,
              !lyricsBody.isEmpty
        else { throw ProviderError.badResponse }

        // 去除 Musixmatch 尾部宣告(通常以「...」結尾並含來源說明)
        let cleaned = lyricsBody
            .components(separatedBy: "\n")
            .filter { !$0.contains("This Lyrics is NOT for Commercial use") }
            .joined(separator: "\n")

        let paragraphs = cleaned
            .components(separatedBy: "\n")
            .map { $0.trimmed }
            .filter { !$0.isEmpty }

        let entries: [(time: TimeInterval, text: String)] = paragraphs.enumerated().map { index, text in
            (TimeInterval(index) * 5, text)
        }
        return LyricsDocument(
            trackID: trackID,
            provider: "Musixmatch",
            isSynced: false,
            lines: Self.buildLines(from: entries)
        )
    }

    // MARK: - 基礎請求

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        guard let url = components.url else { throw ProviderError.badResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LyricFlow/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw ProviderError.badResponse
        }
        return data
    }

    // MARK: - JSON 工具

    private static func messageBody(from data: Data) -> [String: Any]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let body = message["body"] as? [String: Any]
        else { return nil }
        return body
    }

    private static func value(in dict: [String: Any], forKey key: String) -> Any? {
        dict[key]
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let int = any as? Int { return int }
        if let double = any as? Double { return Int(double) }
        if let string = any as? String { return Int(string) }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let double = any as? Double { return double }
        if let int = any as? Int { return Double(int) }
        if let string = any as? String { return Double(string) }
        return nil
    }

    /// 將 (time, text) 陣列轉為 LyricLine(endTime 取下一行起始)。
    static func buildLines(from entries: [(time: TimeInterval, text: String)]) -> [LyricLine] {
        let count = entries.count
        return entries.enumerated().map { index, entry in
            let end: TimeInterval
            if index + 1 < count {
                end = entries[index + 1].time
            } else {
                end = entry.time + 5
            }
            return LyricLine(index: index, text: entry.text, startTime: max(entry.time, 0), endTime: end)
        }
    }
}
