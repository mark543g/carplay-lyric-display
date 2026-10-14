import SwiftUI

/// App 內懸浮歌詞浮層:可拖曳、置頂於 App 任何頁面之上,
/// 顯示當前雙語歌詞行;點兩下開合譯文。
///
/// (跨 App 的懸浮窗由「畫中畫」提供,見 PiPLyricsController。)
struct FloatingLyricsOverlay: View {

    @EnvironmentObject private var center: PlaybackCenter
    @EnvironmentObject private var settings: SettingsStore

    @State private var dragOffset: CGSize = .zero
    @State private var isCompact = false
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            let anchor = anchorPoint(in: proxy.size)

            content
                .position(
                    x: anchor.x + dragOffset.width,
                    y: anchor.y + dragOffset.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            // 把新位置寫回設定(正規化)
                            let newX = min(max((anchor.x + value.translation.width) / proxy.size.width, 0.1), 0.9)
                            let newY = min(max((anchor.y + value.translation.height) / proxy.size.height, 0.05), 0.9)
                            settings.overlayPosition = CGPoint(x: newX, y: newY)
                            dragOffset = .zero
                        }
                )
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                        appeared = true
                    }
                }
        }
        // GeometryReader 填滿 RootView overlay 空間;content 以 .position 絕對定位
        .allowsHitTesting(true)
    }

    private func anchorPoint(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * settings.overlayPosition.x,
            y: size.height * settings.overlayPosition.y
        )
    }

    private var content: some View {
        VStack(spacing: 4) {
            if isCompact {
                Text(center.currentLine?.text ?? "♪")
                    .font(.footnote.bold())
                    .lineLimit(1)
            } else {
                Text(center.currentLine?.text ?? "♪")
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let translation = center.currentLineTranslation, !translation.isEmpty, settings.showTranslation {
                    Text(translation)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.72), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(colors: [.pink.opacity(0.8), .indigo.opacity(0.8)],
                                   startPoint: .leading, endPoint: .trailing),
                    lineWidth: 1
                )
        )
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
        .opacity(appeared ? 1 : 0)
        .frame(minWidth: isCompact ? 120 : 180, maxWidth: isCompact ? 160 : 280)
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                isCompact.toggle()
            }
        }
        .contextMenu {
            Button {
                settings.overlayEnabled = false
            } label: {
                Label("關閉懸浮歌詞", systemImage: "xmark.circle")
            }
            Button {
                isCompact.toggle()
            } label: {
                Label(isCompact ? "展開" : "縮小", systemImage: isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
            }
        }
    }
}
