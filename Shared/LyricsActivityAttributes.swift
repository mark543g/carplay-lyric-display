import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Live Activity(鎖定畫面 / 立動島 / CarPlay 儀表板 / Apple Watch Smart Stack)的屬性定義。
/// 此檔同時編入主 App 與 Widget 擴充功能 target。
public struct LyricsActivityAttributes: ActivityAttributes, Sendable {
    /// 活動期間不變的資訊(換歌時會結束舊活動、建立新活動)。
    public var trackTitle: String
    public var artist: String
    public var sourceName: String

    public init(trackTitle: String, artist: String, sourceName: String) {
        self.trackTitle = trackTitle
        self.artist = artist
        self.sourceName = sourceName
    }

    /// 每次歌詞行推進時更新的內容。
    public struct ContentState: Codable, Hashable, Sendable {
        /// 當前歌詞行原文。
        public var line: String
        /// 當前歌詞行譯文(尚未翻譯完成時為 nil)。
        public var translation: String?
        /// 下一行原文(供擴展區域預覽)。
        public var nextLine: String?
        /// 是否播放中。
        public var isPlaying: Bool
        /// 當前行播報進度 0~1(卡拉 OK 式)。
        public var lineProgress: Double

        public init(line: String, translation: String?, nextLine: String?, isPlaying: Bool, lineProgress: Double) {
            self.line = line
            self.translation = translation
            self.nextLine = nextLine
            self.isPlaying = isPlaying
            self.lineProgress = lineProgress
        }
    }
}
