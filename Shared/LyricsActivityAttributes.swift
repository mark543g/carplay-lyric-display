import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Live Activity(鎖定畫面 / 立動島 / CarPlay 儀表板 / Apple Watch Smart Stack)的屬性定義。
/// 此檔同時編入主 App 與 Widget 擴充功能 target。
///
/// [重要] 曲目資訊放在 **ContentState(動態)** 而非 attributes(靜態),
/// 因為活動「只能在 App 前景建立」;把曲目/歌詞都做成動態後,
/// 只需在前景建立一次,之後換歌/換行都可用 `update()` 在背景更新,
/// 不必每首歌重新 `request()`(背景 request 會失敗 → CarPlay 上永遠不出現)。
public struct LyricsActivityAttributes: ActivityAttributes, Sendable {
    public init() {}

    /// 每次換歌 / 歌詞行推進時更新的內容。
    public struct ContentState: Codable, Hashable, Sendable {
        /// 曲目資訊(動態:換歌時更新,不重建活動)。
        public var trackTitle: String
        public var artist: String
        public var sourceName: String
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

        public init(trackTitle: String,
                    artist: String,
                    sourceName: String,
                    line: String,
                    translation: String?,
                    nextLine: String?,
                    isPlaying: Bool,
                    lineProgress: Double) {
            self.trackTitle = trackTitle
            self.artist = artist
            self.sourceName = sourceName
            self.line = line
            self.translation = translation
            self.nextLine = nextLine
            self.isPlaying = isPlaying
            self.lineProgress = lineProgress
        }
    }
}
