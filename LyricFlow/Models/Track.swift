import Foundation

/// 正在播放 / 被辨識出的曲目。
public struct Track: Identifiable, Hashable, Codable, Sendable {
    /// 穩定識別碼(來源 + 標題 + 歌手),作為歌詞與翻譯快取的 key。
    public var id: String
    public var title: String
    public var artist: String
    public var album: String?
    /// 歌曲總長(秒);用來與歌詞庫比對精準度。
    public var duration: TimeInterval
    public var source: MusicSource
    /// ISRC(Musixmatch 精準比對用;Apple Music 來源盡可能帶入)。
    public var isrc: String?
    /// Spotify 曲目 URI(如 spotify:track:xxxx)。
    public var spotifyURI: String?
    /// 專輯封面 PNG(縮圖,供 Widget / CarPlay 使用)。
    public var artworkPNG: Data?

    public init(id: String, title: String, artist: String, album: String? = nil,
                duration: TimeInterval, source: MusicSource,
                isrc: String? = nil, spotifyURI: String? = nil, artworkPNG: Data? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.source = source
        self.isrc = isrc
        self.spotifyURI = spotifyURI
        self.artworkPNG = artworkPNG
    }

    /// 依來源與曲目資訊合成穩定 ID。
    public static func makeID(title: String, artist: String, source: MusicSource) -> String {
        let normalized = "\(source.rawValue)|\(title.lowercased().trimmed)|\(artist.lowercased().trimmed)"
        return normalized
    }
}

extension String {
    /// 去除前後空白與多餘字元,供比對使用。
    public var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
