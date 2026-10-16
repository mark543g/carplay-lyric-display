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
            // [自我診斷] 打開 App 即顯示「歌詞卡為何不在」的第一個原因,點擊直接修復:
            // 橙 = 本 App 的「即時活動」開關被關掉(過去完全靜默 → 現在直接說明白)
            // 紅 = iOS 系統未允許即時活動
            // 橘 = 授權正常但卡片建立失敗(附上失敗原因)
            if !settings.liveActivityEnabled {
                Button {
                    settings.liveActivityEnabled = true
                    if let track = center.track {
                        center.refreshLiveActivity(track: track)
                    }
                } label: {
                    statusBanner("「即時活動」已關閉:鎖定畫面 / CarPlay 不會顯示歌詞卡 · 點此開啟",
                                 color: .orange)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 4)
            } else if !center.liveActivityAuthorized {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    statusBanner("系統未允許即時活動:鎖定畫面 / CarPlay 不會顯示歌詞卡 · 點此開啟設定",
                                 color: .red)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 4)
            } else if center.track != nil, !center.liveActivityActive {
                statusBanner("歌詞卡未建立(鎖定畫面將無歌詞):\(center.liveActivityLastError ?? "原因不明")",
                             color: .orange)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
        }
        .overlay(alignment: .top) {
            if settings.overlayEnabled {
                FloatingLyricsOverlay()
            }
        }
    }

    private func statusBanner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: 340)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 14))
    }
}
