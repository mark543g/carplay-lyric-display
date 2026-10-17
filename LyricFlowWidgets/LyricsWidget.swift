import WidgetKit
import SwiftUI
import UIKit

// MARK: - Timeline 條目

struct LyricsWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
    /// 此條目時間點作用中的歌詞行(依 position 與 updatedAt 換算)。
    let activeLine: LyricsLineSnapshot?
    /// 條目時間點對應的歌曲位置(供進度環)。
    let songTime: TimeInterval
}

// MARK: - Timeline Provider

/// 核心:把「整首歌」的逐行歌詞變成一批未來條目,
/// 單次 Timeline 請求即涵蓋整曲 → 精準換行、不受刷新預算限制。
struct LyricsTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> LyricsWidgetEntry {
        makeSampleEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricsWidgetEntry) -> Void) {
        completion(Self.currentEntry(from: SharedStore.loadSnapshot(), at: Date()) ?? makeSampleEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricsWidgetEntry>) -> Void) {
        let now = Date()

        guard let snapshot = SharedStore.loadSnapshot() else {
            completion(Timeline(
                entries: [LyricsWidgetEntry(date: now, snapshot: nil, activeLine: nil, songTime: 0)],
                policy: .after(now.addingTimeInterval(600))
            ))
            return
        }

        // 未播放 / 無同步歌詞:單一靜態條目,10 分鐘後再看
        guard snapshot.isPlaying, snapshot.hasSyncedLyrics, !snapshot.lines.isEmpty else {
            let staticEntry = Self.currentEntry(from: snapshot, at: now)
                ?? LyricsWidgetEntry(date: now, snapshot: snapshot, activeLine: nil, songTime: snapshot.position)
            completion(Timeline(entries: [staticEntry], policy: .after(now.addingTimeInterval(600))))
            return
        }

        var entries: [LyricsWidgetEntry] = []
        entries.reserveCapacity(min(snapshot.lines.count, 400) + 1)

        // 1) 當前條目
        if let current = Self.currentEntry(from: snapshot, at: now) {
            entries.append(current)
        }

        // 2) 未來各行(換算牆鐘時間)
        for line in snapshot.lines where line.start > snapshot.position {
            let fireDate = snapshot.wallDate(atSongTime: line.start)
            guard fireDate > now else { continue }
            entries.append(LyricsWidgetEntry(
                date: fireDate,
                snapshot: snapshot,
                activeLine: line,
                songTime: line.start
            ))
            if entries.count >= 400 { break }
        }

        // 3) 歌曲結束條目
        let songEnd = snapshot.duration > 0 ? snapshot.duration : snapshot.position + 300
        let endDate = max(snapshot.wallDate(atSongTime: songEnd), now.addingTimeInterval(10))
        entries.append(LyricsWidgetEntry(
            date: endDate,
            snapshot: snapshot,
            activeLine: nil,
            songTime: songEnd
        ))

        let reloadPolicy: TimelineReloadPolicy = .after(endDate.addingTimeInterval(30))
        completion(Timeline(entries: entries, policy: reloadPolicy))
    }

    // MARK: - 條目建構

    static func currentEntry(from snapshot: NowPlayingSnapshot?, at date: Date) -> LyricsWidgetEntry? {
        guard let snapshot else { return nil }
        let elapsed = date.timeIntervalSince(snapshot.updatedAt)
        let songTime = snapshot.isPlaying ? snapshot.position + max(elapsed, 0) : snapshot.position
        let activeLine = Self.line(at: songTime, in: snapshot)
        return LyricsWidgetEntry(date: date, snapshot: snapshot, activeLine: activeLine, songTime: songTime)
    }

    static func line(at songTime: TimeInterval, in snapshot: NowPlayingSnapshot) -> LyricsLineSnapshot? {
        guard snapshot.hasSyncedLyrics else { return nil }
        var result: LyricsLineSnapshot?
        for line in snapshot.lines where line.start <= songTime {
            result = line
        }
        return result
    }

    private func makeSampleEntry() -> LyricsWidgetEntry {
        let line = LyricsLineSnapshot(text: "跟著旋律一起唱", translation: "Sing along with the melody", start: 0, end: 5)
        let snapshot = NowPlayingSnapshot(
            trackID: "sample",
            title: "示範歌曲",
            artist: "LyricFlow",
            source: MusicSource.appleMusic.rawValue,
            isPlaying: true,
            duration: 210,
            hasSyncedLyrics: true,
            lines: [line],
            position: 0
        )
        return LyricsWidgetEntry(date: .now, snapshot: snapshot, activeLine: line, songTime: 32)
    }
}

// MARK: - Widget 定義

struct LyricsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: AppConstants.lyricsWidgetKind,
            provider: LyricsTimelineProvider()
        ) { entry in
            LyricsWidgetView(entry: entry)
        }
        .configurationDisplayName("動態歌詞")
        .description("即時雙語歌詞:桌面、鎖定畫面、StandBy 與 CarPlay。")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryCircular,
        ])
        // CarPlay / StandBy 的小工具庫只收「背景可移除」的 widget。
        // 只靠 .containerBackground 是隱含可移除,系統可能不列入清單;
        // 明確宣告後才會出現在 StandBy 與 CarPlay。
        .containerBackgroundRemovable(true)
    }
}

// MARK: - Widget View

struct LyricsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: LyricsWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallLyricsView(entry: entry)
            case .systemMedium:
                MediumLyricsView(entry: entry)
            case .systemLarge:
                LargeLyricsView(entry: entry)
            case .accessoryRectangular:
                RectangularLyricsView(entry: entry)
            case .accessoryCircular:
                CircularLyricsView(entry: entry)
            default:
                SmallLyricsView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            // 注意:此閉包是 @ViewBuilder,AnyGradient 不符合 View(編譯錯誤),
            // 需用 Color 或明確的 LinearGradient
            Color.black
        }
        // 背景(含 CarPlay/StandBy 移除支援)由上方的 containerBackground(for: .widget) 完整處理:
        // 使用 containerBackground 即代表背景「可移除」,無需再額外宣告
    }
}

// MARK: - 小型(主畫面 / StandBy / CarPlay)

private struct SmallLyricsView: View {
    let entry: LyricsWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ArtworkDot(entry: entry)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.snapshot?.title ?? "LyricFlow")
                        .font(.caption.bold())
                        .lineLimit(1)
                    Text(entry.snapshot?.artist ?? "未播放")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 4)

            Text(entry.activeLine?.text ?? "♪")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)

            if let translation = entry.activeLine?.translation, !translation.isEmpty {
                Text(translation)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 中型

private struct MediumLyricsView: View {
    let entry: LyricsWidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            ArtworkDot(entry: entry, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.snapshot?.title ?? "未播放")
                    .font(.footnote.bold())
                    .lineLimit(1)
                Text(entry.activeLine?.text ?? "開始播放後顯示歌詞")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let translation = entry.activeLine?.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 大型

private struct LargeLyricsView: View {
    let entry: LyricsWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArtworkDot(entry: entry, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.snapshot?.title ?? "未播放")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(entry.snapshot?.artist ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "music.note")
                    .foregroundStyle(.pink)
            }

            Spacer(minLength: 8)

            Text(entry.activeLine?.text ?? "♪")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let translation = entry.activeLine?.translation, !translation.isEmpty {
                Text(translation)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 接下來兩行
            if let snapshot = entry.snapshot, let active = entry.activeLine,
               let index = snapshot.lines.firstIndex(where: { $0.start == active.start }) {
                ForEach(1...2, id: \.self) { offset in
                    let nextIndex = index + offset
                    if nextIndex < snapshot.lines.count {
                        Text(snapshot.lines[nextIndex].text)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            // 歌曲進度條
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(LinearGradient(colors: [.pink, .indigo], startPoint: .leading, endPoint: .trailing))
                        .frame(width: progressWidth(in: proxy.size.width))
                }
            }
            .frame(height: 4)
        }
    }

    private func progressWidth(in total: CGFloat) -> CGFloat {
        let duration = entry.snapshot?.duration ?? 0
        guard duration > 0 else { return 0 }
        return total * CGFloat(min(max(entry.songTime / duration, 0), 1))
    }
}

// MARK: - 鎖定畫面配件

private struct RectangularLyricsView: View {
    let entry: LyricsWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // [build 42] 字體放大:歌詞 footnote → title3,原標題列讓位給大字歌詞
            Text(entry.activeLine?.text ?? fallbackInfo)
                .font(.title3.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if entry.activeLine != nil, let snap = entry.snapshot {
                Text("\(snap.title) · \(snap.artist)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 無歌詞行時以大字顯示歌名・歌手。
    private var fallbackInfo: String {
        guard let s = entry.snapshot else { return "LyricFlow" }
        return s.artist.isEmpty ? s.title : "\(s.title) · \(s.artist)"
    }
}

private struct CircularLyricsView: View {
    let entry: LyricsWidgetEntry

    var body: some View {
        let duration = entry.snapshot?.duration ?? 0
        let fraction = duration > 0 ? min(max(entry.songTime / duration, 0), 1) : 0

        ZStack {
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.pink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "music.note")
                .font(.caption.bold())
        }
    }
}

// MARK: - 小工具

/// 封面小圖(有 PNG 用 PNG,否則漸層圓)。
private struct ArtworkDot: View {
    let entry: LyricsWidgetEntry
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [.pink.opacity(0.8), .indigo.opacity(0.9)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            if let data = entry.snapshot?.artworkPNG, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}
