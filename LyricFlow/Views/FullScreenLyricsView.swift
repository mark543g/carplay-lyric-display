import SwiftUI

/// 雙語全螢幕歌詞:卡拉 OK 式高亮、自動捲動、點行跳轉。
struct FullScreenLyricsView: View {

    @Binding var isPresented: Bool

    @EnvironmentObject private var center: PlaybackCenter
    @EnvironmentObject private var settings: SettingsStore

    @State private var autoScroll = true

    var body: some View {
        ZStack {
            background

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        header

                        switch center.lyricsState {
                        case .loading:
                            ProgressView("搜尋歌詞中…")
                                .padding(.top, 120)
                        case .notFound, .failed:
                            VStack(spacing: 12) {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("找不到此曲歌詞")
                                    .font(.headline)
                                Button("重試") { center.refreshLyrics() }
                                    .buttonStyle(.borderedProminent)
                            }
                            .padding(.top, 120)
                        default:
                            lyricLines(proxy: proxy)
                        }

                        Color.clear.frame(height: UIScreen.main.bounds.height * 0.45)
                    }
                    .padding(.horizontal, 24)
                }
                .onChange(of: center.currentLineIndex) { _, newIndex in
                    guard autoScroll, let newIndex else { return }
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo("line-\(newIndex)", anchor: .center)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                Toggle("自動捲動", isOn: $autoScroll)
                    .toggleStyle(.button)
                    .font(.caption)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if let line = center.currentLine {
                Text("\(center.currentLineIndex.map { "第 \($0 + 1) 行" } ?? "")·\(settings.targetLanguageName)")
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 14)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            if let data = center.track?.artworkPNG, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .blur(radius: 42)
                    .overlay(.black.opacity(0.55))
            } else {
                LinearGradient(
                    colors: [.pink.opacity(0.35), .indigo.opacity(0.55), .black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - 頂部曲目資訊

    private var header: some View {
        VStack(spacing: 6) {
            Text(center.track?.title ?? "")
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(center.track?.artist ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.top, 64)
        .padding(.bottom, 18)
    }

    // MARK: - 歌詞列表

    private func lyricLines(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 2) {
            if let lyrics = center.lyrics, !lyrics.lines.isEmpty {
                ForEach(lyrics.lines) { line in
                    let isActive = line.index == center.currentLineIndex
                    Button {
                        autoScroll = false
                        center.seek(to: line.startTime + 0.2)
                        // 點擊後短暫恢復自動捲動
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            await MainActor.run { autoScroll = true }
                        }
                    } label: {
                        BilingualLineView(
                            text: line.text,
                            translation: lyrics.translations[line.index],
                            isActive: isActive
                        )
                    }
                    .buttonStyle(.plain)
                    .id("line-\(line.index)")
                    .padding(.horizontal, 8)
                }
            } else {
                Text(center.lyricsState == .loading ? "歌詞載入後即可顯示" : "尚無歌詞")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
            }
        }
    }
}
