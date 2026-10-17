import WidgetKit
import SwiftUI

/// Widget 擴充功能進入點:
/// 1. LyricsWidget —— 主畫面小工具(systemSmall/Medium/Large)、
///    鎖定畫面配件(accessoryRectangular/Circular)、StandBy、CarPlay 小工具
///    (iOS 26:支援 systemSmall 即自動出現在 CarPlay)
///    (build 45:accessoryInline 已放棄 — 鎖定畫面完全不更新,平台行為)
/// 2. LyricsLiveActivity —— 即時活動(預設停用,build 42;鎖定畫面 / 動態島 / CarPlay 儀表板 / Apple Watch Smart Stack)
@main
struct LyricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsWidget()
        LyricsLiveActivity()
    }
}
