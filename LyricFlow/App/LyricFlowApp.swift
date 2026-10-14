import SwiftUI

/// App 進入點。
@main
struct LyricFlowApp: App {

    @StateObject private var center = PlaybackCenter.shared
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var recognition = RecognitionService.shared
    @StateObject private var pip = PiPLyricsController.shared
    @StateObject private var spotify = SpotifyService.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(center)
                .environmentObject(settings)
                .environmentObject(recognition)
                .environmentObject(pip)
                .environmentObject(spotify)
                .tint(.pink)
                .onAppear {
                    center.start()
                }
                .onOpenURL { url in
                    // Spotify App Remote 授權回跳
                    SpotifyService.shared.handleOpenURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // 回前景:若曾連線 Spotify,嘗試恢復 App Remote 連線
                        if settings.spotifyConnectedOnce, !settings.spotifyClientID.trimmed.isEmpty {
                            SpotifyService.shared.reconnectIfPossible()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .pipLyricsDidRequestRestore)) { _ in
                    // PiP 關閉時點回 App;無需額外處理,前景已可顯示
                }
        }
    }
}
