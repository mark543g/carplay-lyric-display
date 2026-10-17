import WidgetKit
import SwiftUI

/// Widget 擴充功能進入點:
/// 1. LyricsWidget —— 桌面小工具(systemSmall/Medium/Large)、
///    鎖定畫面配件(accessoryInline/Rectangular/Circular)、StandBy、CarPlay 小工具
///    (iOS 26:支援 systemSmall 即自動出現在 CarPlay)
/// 2. LyricsLiveActivity —— 即時活動(鎖定畫面 / 立動島 / CarPlay 儀表板 / Apple Watch Smart Stack)
@main
struct LyricsWidgetBundle: WidgetBundle {
    var body: some Widget {
        LyricsWidget()
        LyricsLiveActivity()
    }
}
