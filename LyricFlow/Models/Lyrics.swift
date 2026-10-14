import Foundation

/// 單行歌詞(帶時間軸)。
public struct LyricLine: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let text: String
    /// 行起始時間(秒)。
    public let startTime: TimeInterval
    /// 行結束時間(秒;下一行起始或歌曲結尾)。
    public let endTime: TimeInterval

    public init(index: Int, text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.index = index
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }

    public var duration: TimeInterval { max(endTime - startTime, 0) }
}

/// 一份完整歌詞文件。
public struct LyricsDocument: Codable, Sendable {
    public var trackID: String
    public var provider: String
    /// 是否含時間同步資訊;false 時僅能捲動展示、無法逐行高亮。
    public var isSynced: Bool
    public var lines: [LyricLine]

    public init(trackID: String, provider: String, isSynced: Bool, lines: [LyricLine]) {
        self.trackID = trackID
        self.provider = provider
        self.isSynced = isSynced
        self.lines = lines
    }

    /// 逐行譯文,以行 index 為 key。
    public var translations: [Int: String] = [:]

    /// 目前/下一行,供 Live Activity 與小工具顯示。
    public func line(at position: TimeInterval) -> (index: Int, line: LyricLine)? {
        guard isSynced, !lines.isEmpty else { return nil }
        // 二分搜尋最後一個 startTime <= position 的行
        var low = 0, high = lines.count - 1, found = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].startTime <= position {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard found >= 0 else { return nil }
        return (found, lines[found])
    }

    /// 行內播放進度(0~1),供卡拉 OK 式高亮。
    public func lineProgress(at position: TimeInterval) -> Double {
        guard let current = line(at: position), current.line.duration > 0 else { return 0 }
        let fraction = (position - current.line.startTime) / current.line.duration
        return min(max(fraction, 0), 1)
    }

    /// 對應的 Widget 快照行陣列。
    public func snapshotLines(translations included: Bool) -> [LyricsLineSnapshot] {
        lines.map { line in
            LyricsLineSnapshot(
                text: line.text,
                translation: translations[line.index],
                start: line.startTime,
                end: line.endTime
            )
        }
    }
}
