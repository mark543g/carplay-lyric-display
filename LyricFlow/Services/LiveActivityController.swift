import Foundation
import ActivityKit

/// Live Activity 控制器(鎖定畫面 / 立動島 / CarPlay 儀表板 / Apple Watch Smart Stack)。
@MainActor
final class LiveActivityController {

    private var activity: Activity<LyricsActivityAttributes>?

    var isActive: Bool {
        activity != nil
    }

    /// 是否允許建立(系統設定 + 使用者設定)。
    var canStart: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 換歌時呼叫:結束舊活動、建立新活動。
    func startActivity(track: Track, initial state: LyricsActivityAttributes.ContentState) {
        end()

        guard canStart else { return }
        let attributes = LyricsActivityAttributes(
            trackTitle: track.title,
            artist: track.artist,
            sourceName: track.source.displayName
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
        activity = try? Activity.request(attributes: attributes, content: content)
    }

    /// 歌詞行推進 / 播放狀態改變時呼叫。
    func update(state: LyricsActivityAttributes.ContentState) {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
        Task {
            await activity.update(content)
        }
    }

    /// 播放停止 / App 結束時呼叫。
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(dismissalPolicy: .immediate)
        }
    }
}
