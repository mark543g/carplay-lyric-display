import SwiftUI

/// 識歌模式:以 ShazamKit 辨識環境音樂,結果可直接載入歌詞。
struct RecognitionView: View {

    @EnvironmentObject private var center: PlaybackCenter
    @EnvironmentObject private var recognition: RecognitionService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    listenButton
                    resultCard
                    historyHint
                }
                .padding(24)
            }
            .navigationTitle("識歌模式")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 聆聽按鈕

    private var listenButton: some View {
        VStack(spacing: 14) {
            Button {
                if recognition.state == .listening {
                    recognition.stopListening()
                } else {
                    recognition.startListening()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: recognition.state == .listening
                                    ? [.pink, .purple]
                                    : [Color.pink.opacity(0.65), Color.indigo.opacity(0.8)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 170, height: 170)
                        .shadow(color: .pink.opacity(0.45), radius: 24, y: 10)

                    if recognition.state == .listening {
                        // 聲波動畫
                        HStack(spacing: 6) {
                            ForEach(0..<5, id: \.self) { index in
                                Capsule()
                                    .fill(.white)
                                    .frame(width: 6, height: CGFloat([24, 44, 34, 52, 30][index]))
                                    .symbolEffect(.pulse, options: .repeating)
                                    .animation(
                                        .easeInOut(duration: 0.5)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.08),
                                        value: recognition.state
                                    )
                            }
                        }
                    } else {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 56))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(recognition.state == .listening ? "正在聆聽環境音樂…" : "點一下開始辨識")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: - 結果

    @ViewBuilder
    private var resultCard: some View {
        switch recognition.state {
        case .noMatch:
            VStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("沒有找到符合的歌曲")
                    .font(.headline)
            }
            .padding(.vertical, 24)

        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)

        case .matched:
            if let track = recognition.recognizedTrack {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        ArtworkView(artworkPNG: track.artworkPNG, cornerRadius: 14)
                            .frame(width: 84, height: 84)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.headline)
                                .lineLimit(2)
                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let isrc = track.isrc {
                                Text("ISRC: \(isrc)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button {
                            center.loadRecognizedTrack(track)
                        } label: {
                            Label("載入動態歌詞", systemImage: "text.badge.star")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        if let url = recognition.appleMusicURL {
                            Link(destination: url) {
                                Label("在 Apple Music 查看", systemImage: "music.note")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }

        default:
            EmptyView()
        }
    }

    private var historyHint: some View {
        Text("辨識結果會以「識歌模式」來源顯示歌詞與翻譯;\n實際播放仍由原 App 控制。")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}
