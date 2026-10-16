import SwiftUI
import UIKit

/// 主畫面:播放(預設)/ 識歌 / 設定 三個分頁 + 懸浮歌詞浮層。
struct RootView: View {

    @EnvironmentObject private var center: PlaybackCenter
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        TabView {
            NowPlayingView()
                .tabItem { Label("播放", systemImage: "play.circle.fill") }
            RecognitionView()
                .tabItem { Label("識歌", systemImage: "waveform.badge.magnifyingglass") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
        }
        .overlay(alignment: .top) {
            if settings.overlayEnabled {
                FloatingLyricsOverlay()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            LiveActivityStatusRow()
        }
    }
}

/// 即時活動被 iOS 擋下時的自我修復提示列:
/// 只在「App 內已開啟即時活動 + 有曲目 + 活動沒建起來」時出現,
/// 附一鍵開啟 iOS 設定(本 App 頁面,即時活動開關所在位置)的按鈕;
/// 一切正常時完全不顯示,零干擾。
private struct LiveActivityStatusRow: View {

    @EnvironmentObject private var center: PlaybackCenter
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        if settings.liveActivityEnabled, center.track != nil, !center.liveActivityActive {
            if !center.liveActivityAuthorized {
                row(text: "iOS 已停用 LyricFlow 的即時活動,鎖定畫面不會出現歌詞卡")
            } else if let error = center.liveActivityLastError {
                row(text: "即時活動建立失敗:\(error)")
            }
        }
    }

    private func row(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Button("開啟設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12), in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}
