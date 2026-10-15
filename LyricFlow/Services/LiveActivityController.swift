import Foundation
import ActivityKit

/// Live Activity 控制器(鎖定畫面 / 立動島 / CarPlay 儀表板 / Apple Watch Smart Stack)。
@MainActor
final class LiveActivityController {

    private var activity: Activity<LyricsActivityAttributes>?

    /// 最近一次啟動活動的失敗原因(供設定頁診斷顯示;成功時清空)。
    private(set) var lastError: String?

    var isActive: Bool {
        activity != nil
    }

    /// 系統是否允許即時活動(iPhone「設定 → 歌詞行 → 即時活動」)。
    var authorizationEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 換歌時呼叫:結束舊活動、建立新活動。回傳是否成功建立。
    @discardableResult
    func startActivity(track: Track, initial state: LyricsActivityAttributes.ContentState) -> Bool {
        end()

        guard authorizationEnabled else {
            lastError = "系統未允許即時活動(設定 → 歌詞行 → 即時活動)"
            return false
        }

        let attributes = LyricsActivityAttributes(
            trackTitle: track.title,
            artist: track.artist,
            sourceName: track.source.displayName
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
        do {
            activity = try Activity.request(attributes: attributes, content: content)
            lastError = nil
            return true
        } catch {
            activity = nil
            lastError = "\(error)"
            return false
        }
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
