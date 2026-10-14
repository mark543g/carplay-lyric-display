import Foundation

/// .lrc 格式解析器(LRCLIB 與多數歌詞庫使用)。
///
/// 支援:
/// - 多重時間標籤:`[00:12.30][00:45.10]歌詞`
/// - `mm:ss.xx`、`mm:ss.xxx`、`mm:ss:xx` 時間格式
/// - `[offset:±ms]` 全域位移
/// - `[ti:]`、`[ar:]`、`[al:]` 詮釋資料
public enum LRCParser {

    public struct ParseResult {
        public var lines: [LyricLine]
        public var title: String?
        public var artist: String?
        public var album: String?
        public var offset: TimeInterval
    }

    private static let tagPattern = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    )
    private static let metaPattern = try! NSRegularExpression(
        pattern: #"\[(ti|ar|al|offset):(.*)\]"#
    )

    public static func parse(_ lrc: String) -> ParseResult {
        var entries: [(time: TimeInterval, text: String)] = []
        var title: String?
        var artist: String?
        var album: String?
        var offset: TimeInterval = 0

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // 先剝離所有時間標籤
            let nsLine = line as NSString
            var timestamps: [TimeInterval] = []
            var matchRanges: [NSRange] = []
            let tagMatches = tagPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in tagMatches {
                let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                let fractionRaw = match.numberOfRanges > 3 ? nsLine.substring(with: match.range(at: 3)) : nil
                var fraction = 0.0
                if let fractionRaw {
                    switch fractionRaw.count {
                    case 1: fraction = (Double(fractionRaw) ?? 0) / 10
                    case 2: fraction = (Double(fractionRaw) ?? 0) / 100
                    default: fraction = (Double("0." + fractionRaw) ?? 0)
                    }
                }
                timestamps.append(minutes * 60 + seconds + fraction)
                matchRanges.append(match.range)
            }

            if timestamps.isEmpty {
                // 無時間標籤 → 檢查是否為詮釋資料
                if let meta = metaMatch(nsLine) {
                    switch meta.key {
                    case "ti": title = meta.value
                    case "ar": artist = meta.value
                    case "al": album = meta.value
                    case "offset": offset = (Double(meta.value) ?? 0) / 1000
                    default: break
                    }
                }
                continue
            }

            // 取得標籤之後的純文字
            var textStart = nsLine.length
            for range in matchRanges where range.location < textStart {
                textStart = min(textStart, range.location + range.length)
            }
            // 只把「連續前置」的標籤剝掉(時間標籤後仍可能有少數標籤混排,直接全部剝離亦可)
            let text = stripTrailingTags(nsLine.substring(from: min(textStart, nsLine.length)))
                .trimmingCharacters(in: .whitespaces)
            for timestamp in timestamps where !text.isEmpty {
                entries.append((timestamp + offset, text))
            }
        }

        entries.sort { $0.time < $1.time }

        // 去除相鄰完全重複的行(有些 lrc 會有插曲重複)
        var cleaned: [(time: TimeInterval, text: String)] = []
        for entry in entries {
            if let last = cleaned.last, last.time == entry.time, last.text == entry.text { continue }
            cleaned.append(entry)
        }

        // 依下一行起始時間補上 endTime
        let count = cleaned.count
        let lines: [LyricLine] = cleaned.enumerated().map { index, entry in
            let end: TimeInterval
            if index + 1 < count {
                end = cleaned[index + 1].time
            } else {
                end = entry.time + 5
            }
            return LyricLine(index: index, text: entry.text, startTime: max(entry.time, 0), endTime: end)
        }

        return ParseResult(lines: lines, title: title, artist: artist, album: album, offset: offset)
    }

    /// 把行內混剩的 `[xx:xx.xx]` 標籤清乾淨。
    /// [稽核 F5 修補] 迭代上限 32 次:合法歌詞行不會有超過 32 個前置時間標籤,
    /// 防止惡意輸入(單行塞滿標籤)造成 O(n²) 掃描。
    private static func stripTrailingTags(_ text: String) -> String {
        var result = text
        var iterations = 0
        while let match = result.range(of: #"\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]"#, options: .regularExpression) {
            guard iterations < 32,
                  match.lowerBound == result.startIndex || result[..<match.lowerBound].allSatisfy({ $0.isWhitespace })
            else { break }
            result.removeSubrange(match)
            iterations += 1
        }
        return result
    }

    private static func metaMatch(_ line: NSString) -> (key: String, value: String)? {
        guard let match = metaPattern.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)),
              match.numberOfRanges > 2 else { return nil }
        return (line.substring(with: match.range(at: 1)).lowercased(),
                line.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces))
    }
}
