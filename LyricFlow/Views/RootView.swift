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
            // [診斷] 系統未允許即時活動 → 鎖定畫面 / CarPlay 不會出現歌詞卡。
            // 直接在主畫面醒目提示,並可點擊跳到本 App 的設定頁。
            if settings.liveActivityEnabled, !center.liveActivityAuthorized {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("⚠️ 系統未允許即時活動:鎖定畫面 / CarPlay 不會顯示歌詞卡。點此開啟「設定 → 歌詞行」把「即時活動」打開。")
                        .font(.caption.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(10)
                        .frame(maxWidth: 340)
                        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if settings.overlayEnabled {
                FloatingLyricsOverlay()
            }
        }
    }
}
