import Foundation
import ActivityKit
import UIKit

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
        // App 重啟後,系統可能仍有本 App 的活動。
        // [修正 36] 不再沿用任何舊活動(含 .active):改為「結束舊卡 + 建立全新卡片」。
        // 理由:重裝/重簽/系統內部狀態異常後,活動可能「狀態 .active、App 端全綠,
        // 但鎖定畫面就是不渲染」(已知卡住型態;社群解法是把即時活動開關 off→on,
        // 等同刪卡重建)。建立一張全新 ID 的卡片,讓 iOS 重新評估這張卡的顯示。
        for existing in Activity<LyricsActivityAttributes>.activities {
            let old = existing
            Task { await old.end(dismissalPolicy: .immediate) }
        }
        // [修正] 不再用 areActivitiesEnabled 預先拒絕:反覆安裝/重簽後,
        // iOS 的 per-app 即時活動狀態可能過期失真。一律直接嘗試建立;
        // 若系統真的不允許,由 request() 拋出真正的原因(顯示於 設定 → 關於)。
        do {
            // staleDate nil = 永不過期:歌詞靠逐行推播更新;120 秒的過期日
            // 會在長間奏(>2 分鐘無換行)時把正常內容標成「過時」。
            let created = try Activity.request(
                attributes: LyricsActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil)
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
        if let activity {
            push(activity, state: state)
            return
        }
        // [修正] 前景時自我補建:活動若已被系統回收或先前建立失敗,
        // 下一次換行就重試建立,不必等換歌或回前景。
        // 背景無法 request(系統限制),維持靜默略過。
        guard UIApplication.shared.applicationState == .active else { return }
        ensureActive(state: state)
    }

    private func push(_ activity: Activity<LyricsActivityAttributes>,
                      state: LyricsActivityAttributes.ContentState) {
        updateCount += 1
        let content = ActivityContent(state: state, staleDate: nil) // 永不過期(同上)
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
