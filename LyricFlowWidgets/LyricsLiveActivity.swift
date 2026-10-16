import WidgetKit
import SwiftUI
import ActivityKit

/// 即時活動:鎖定畫面 + 立動島 + CarPlay 儀表板 + Apple Watch Smart Stack。
///
/// iOS 26 關鍵修飾器:
/// - `.supplementalActivityFamilies([.small])`:宣告支援 small 尺寸,
///   CarPlay 會以「activityFamily == .small」的內容呈現(同時相容 Apple Watch)。
struct LyricsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricsActivityAttributes.self) { context in
            LyricsActivityLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note")
                        .foregroundStyle(.pink)
                        .font(.title3)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.circle")
                        .foregroundStyle(.pink.opacity(0.8))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(context.state.trackTitle)
                            .font(.caption2.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(context.state.artist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.line)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        if let translation = context.state.translation, !translation.isEmpty {
                            Text(translation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        ProgressView(value: context.state.lineProgress)
                            .tint(.pink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundStyle(.pink)
            } compactTrailing: {
                Text(context.state.line)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 96, alignment: .trailing)
                    .minimumScaleFactor(0.6)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(.pink)
            }
            .keylineTint(.pink)
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - 鎖定畫面 / CarPlay / Watch Small 視圖

struct LyricsActivityLockScreenView: View {
    @Environment(\.activityFamily) private var activityFamily

    let context: ActivityViewContext<LyricsActivityAttributes>

    var body: some View {
        // [鎖定逐行關鍵] 視圖側自渲染:每秒由系統時鐘重繪,
        // 依 App Group 快照的「牆鐘數學」推算目前行 —— 完全不依賴 App 推播
        // (iOS 對背景送入的即時活動 update() 會節流甚至不套用;
        //  而系統時鐘驅動的重繪不受此限,App 暫停了也照樣換行)。
        // 快照讀不到 / 曲目不符 / 無同步歌詞 → 回退 context.state(= 現況,不會更差)。
        switch activityFamily {
        case .small:
            // CarPlay 儀表板 / Apple Watch Smart Stack:精簡雙行
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let render = Self.renderLine(at: timeline.date, state: context.state)
                smallLayout(render)
            }
        default:
            // iPhone 鎖定畫面:完整雙語 + 卡拉 OK 進度
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let render = Self.renderLine(at: timeline.date, state: context.state)
                fullLayout(render)
            }
        }
    }

    // MARK: - 視圖側自渲染

    /// 視圖端自行算出的「目前行」顯示資料。
    private struct RenderedLine {
        var text: String
        var translation: String?
        var nextLine: String?
        var progress: Double
        /// 播放中且行起訖已知時:絕對時間範圍,交給 `ProgressView(timerInterval:)`
        /// 用系統時鐘自動推進(App 推播被節流也不影響)。
        var karaokeRange: ClosedRange<Date>?
    }

    /// 從 App Group 快照推算目前行。數學與 Widget Timeline 完全相同:
    /// 播放中 `songTime = position + (now - updatedAt)`,否則凍結在 position。
    private static func renderLine(at date: Date,
                                   state: LyricsActivityAttributes.ContentState) -> RenderedLine {
        let fallback = RenderedLine(
            text: state.line,
            translation: state.translation,
            nextLine: state.nextLine,
            progress: state.lineProgress,
            karaokeRange: nil
        )

        guard let snapshot = SharedStore.loadSnapshot(),
              snapshot.title == state.trackTitle, // 曲目不符(換歌瞬間)→ 信任推播內容
              snapshot.hasSyncedLyrics,
              !snapshot.lines.isEmpty
        else { return fallback }

        let elapsed = date.timeIntervalSince(snapshot.updatedAt)
        let songTime = snapshot.isPlaying ? snapshot.position + max(elapsed, 0) : snapshot.position

        guard let active = LyricsTimelineProvider.line(at: songTime, in: snapshot) else {
            return fallback
        }

        var result = RenderedLine(
            text: active.text,
            translation: active.translation,
            nextLine: fallback.nextLine,
            progress: fallback.progress,
            karaokeRange: nil
        )

        if let index = snapshot.lines.firstIndex(where: { $0.start == active.start }),
           index + 1 < snapshot.lines.count {
            result.nextLine = snapshot.lines[index + 1].text
        }

        if let end = active.end, end > active.start {
            result.progress = min(max((songTime - active.start) / (end - active.start), 0), 1)
            // 只有「播放中」才給絕對時間範圍:暫停時牆鐘會繼續走 → 進度條不准。
            if snapshot.isPlaying {
                let startWall = snapshot.wallDate(atSongTime: active.start)
                let endWall = snapshot.wallDate(atSongTime: end)
                if endWall > startWall {
                    result.karaokeRange = startWall...endWall
                }
            }
        }

        return result
    }

    // MARK: - 鎖定畫面完整版

    private func fullLayout(_ render: RenderedLine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .foregroundStyle(.pink)
                Text("\(context.state.trackTitle) — \(context.state.artist)")
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Text(context.state.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(render.text)
                .font(.title3.bold())
                .lineLimit(3)
                .minimumScaleFactor(0.6)

            if let translation = render.translation, !translation.isEmpty {
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            if let next = render.nextLine, !next.isEmpty {
                Text("接下來:\(next)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            karaokeBar(render)
        }
        .padding()
        .widgetURL(URL(string: "lyricflow://nowplaying"))
    }

    // MARK: - CarPlay / Watch Small 精簡版

    private func smallLayout(_ render: RenderedLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.caption2)
                    .foregroundStyle(.pink)
                Text(context.state.trackTitle)
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
            }
            Text(render.text)
                .font(.subheadline.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let translation = render.translation, !translation.isEmpty {
                Text(translation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            karaokeBar(render)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 卡拉 OK 進度條

    @ViewBuilder
    private func karaokeBar(_ render: RenderedLine) -> some View {
        if let range = render.karaokeRange {
            // 系統時鐘自動推進:App 暫停、推播被節流時進度仍持續走。
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.pink)
        } else {
            ProgressView(value: render.progress)
                .tint(.pink)
        }
    }
}
