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
                        Text(context.attributes.trackTitle)
                            .font(.caption2.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(context.attributes.artist)
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
        switch activityFamily {
        case .small:
            // CarPlay 儀表板 / Apple Watch Smart Stack:精簡雙行
            smallLayout
        default:
            // iPhone 鎖定畫面:完整雙語 + 卡拉 OK 進度
            fullLayout
        }
    }

    private var fullLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .foregroundStyle(.pink)
                Text("\(context.attributes.trackTitle) — \(context.attributes.artist)")
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Text(context.attributes.sourceName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(context.state.line)
                .font(.title3.bold())
                .lineLimit(3)
                .minimumScaleFactor(0.6)

            if let translation = context.state.translation, !translation.isEmpty {
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            if let next = context.state.nextLine, !next.isEmpty {
                Text("接下來:\(next)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            ProgressView(value: context.state.lineProgress)
                .tint(.pink)
        }
        .padding()
        .widgetURL(URL(string: "lyricflow://nowplaying"))
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.caption2)
                    .foregroundStyle(.pink)
                Text(context.attributes.trackTitle)
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
            }
            Text(context.state.line)
                .font(.subheadline.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let translation = context.state.translation, !translation.isEmpty {
                Text(translation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ProgressView(value: context.state.lineProgress)
                .tint(.pink)
        }
        .padding(.vertical, 4)
    }
}
