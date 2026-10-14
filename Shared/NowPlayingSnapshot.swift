import Foundation

/// 供 Widget / CarPlay / Live Activity 使用的單行歌詞快照。
public struct LyricsLineSnapshot: Codable, Hashable, Sendable {
    public var text: String
    public var translation: String?
    /// 行起始時間(秒,相對歌曲開頭)。
    public var start: TimeInterval
    /// 行結束時間(秒);若未知則為 nil。
    public var end: TimeInterval?

    public init(text: String, translation: String? = nil, start: TimeInterval, end: TimeInterval? = nil) {
        self.text = text
        self.translation = translation
        self.start = start
        self.end = end
    }
}

/// 「目前播放 + 歌詞」的完整快照,由主 App 寫入、Widget 讀出。
///
/// Widget 以 `position` + `updatedAt` 把每行歌詞的相對時間換算成絕對時間,
/// 產生整首歌的 Timeline 條目(一次請求即可涵蓋整首歌,不受系統刷新預算限制)。
public struct NowPlayingSnapshot: Codable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String?
    public var source: String
    public var isPlaying: Bool
    public var duration: TimeInterval
    public var artworkPNG: Data?
    public var provider: String?
    public var hasSyncedLyrics: Bool
    public var lines: [LyricsLineSnapshot]
    /// 寫入快照當下的播放位置(秒)。
    public var position: TimeInterval
    /// 快照寫入時間。
    public var updatedAt: Date
    /// 寫入時作用中的行索引(供無同步歌詞時的 fallback 顯示)。
    public var lineIndex: Int?

    public init(trackID: String, title: String, artist: String, album: String? = nil,
                source: String, isPlaying: Bool, duration: TimeInterval,
                artworkPNG: Data? = nil, provider: String? = nil,
                hasSyncedLyrics: Bool, lines: [LyricsLineSnapshot],
                position: TimeInterval, updatedAt: Date = Date(), lineIndex: Int? = nil) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.source = source
        self.isPlaying = isPlaying
        self.duration = duration
        self.artworkPNG = artworkPNG
        self.provider = provider
        self.hasSyncedLyrics = hasSyncedLyrics
        self.lines = lines
        self.position = position
        self.updatedAt = updatedAt
        self.lineIndex = lineIndex
    }

    /// 將歌曲內的相對時間換算成牆鐘時間(僅在播放中有效)。
    public func wallDate(atSongTime songTime: TimeInterval) -> Date {
        updatedAt.addingTimeInterval(songTime - position)
    }
}

/// App Group 快取讀寫器(主 App 寫入;Widget / CarPlay 讀取)。
public enum SharedStore {
    private static let snapshotKey = "nowPlayingSnapshot"

    public static func saveSnapshot(_ snapshot: NowPlayingSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            AppConstants.sharedDefaults.set(data, forKey: snapshotKey)
        }
    }

    public static func loadSnapshot() -> NowPlayingSnapshot? {
        guard let data = AppConstants.sharedDefaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
    }

    // MARK: - 翻譯快取(trackID + 語言 → 逐行譯文)

    private static func translationKey(trackID: String, language: String) -> String {
        "tr-\(trackID)-\(language)"
    }

    public static func saveTranslations(_ map: [String: String], trackID: String, language: String) {
        if let data = try? JSONEncoder().encode(map) {
            AppConstants.sharedDefaults.set(data, forKey: translationKey(trackID: trackID, language: language))
        }
    }

    public static func loadTranslations(trackID: String, language: String) -> [String: String]? {
        guard let data = AppConstants.sharedDefaults.data(forKey: translationKey(trackID: trackID, language: language)) else {
            return nil
        }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}
