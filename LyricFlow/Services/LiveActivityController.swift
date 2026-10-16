import Foundation
import ActivityKit

/// Live Activity 控制器(鎖定畫面 / 立動島 / CarPlay 儀表板 / Apple Watch Smart Stack)。
///
/// [關鍵] 活動「只能在 App 前景建立」。因此本控制器採「前景建立一次、之後只 update」:
/// 曲目與歌詞都放在 ContentState(動態),換歌/換行都用 `update()`(背景亦可),
/// 不再每首歌重新 `request()`(背景 request 會失敗,導致 CarPlay 上永不出現)。
@MainActor
final class LiveActivityController {

    private var activity: Activity<LyricsActivityAttributes>?

    /// 最近一次啟動活動的失敗原因(供設定頁診斷顯示;成功時清空)。
    private(set) var lastError: String?

    /// 已送出幾次活動更新(診斷用:鎖定後數字若不增加 = App 沒在更新)。
    private(set) var updateCount = 0

    var isActive: Bool { activity != nil }

    /// 系統是否允許即時活動(iPhone「設定 → 歌詞行 → 即時活動」)。
    var authorizationEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 前景時呼叫:尚無活動則建立;已有活動則更新內容。回傳是否已有(或成功建立)活動。
    @discardableResult
    func ensureActive(state: LyricsActivityAttributes.ContentState) -> Bool {
        if let activity {
            push(activity, state: state)
            return true
        }
        // App 重啟後,系統可能仍有本 App 的活動 → 接回來用,不要重複建立。
        if let existing = Activity<LyricsActivityAttributes>.activities.first {
            activity = existing
            push(existing, state: state)
            return true
        }
        guard authorizationEnabled else {
            lastError = "系統未允許即時活動(設定 → 歌詞行 → 即時活動)"
            return false
        }
        do {
            let created = try Activity.request(
                attributes: LyricsActivityAttributes(),
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
            )
            activity = created
            lastError = nil
            return true
        } catch {
            lastError = "\(error)"
            return false
        }
    }

    /// 內容更新(換歌或換行時呼叫;可在背景執行)。
    func update(state: LyricsActivityAttributes.ContentState) {
        guard let activity else { return }
        push(activity, state: state)
    }

    private func push(_ activity: Activity<LyricsActivityAttributes>,
                      state: LyricsActivityAttributes.ContentState) {
        updateCount += 1
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
