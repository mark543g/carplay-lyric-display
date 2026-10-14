import SwiftUI

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
    }
}
