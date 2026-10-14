import SwiftUI
import UIKit

// MARK: - 專輯封面

/// 專輯封面(支援 Track 內嵌 PNG);無封面時顯示漸層 + 音符圖示。
struct ArtworkView: View {
    let artworkPNG: Data?
    var cornerRadius: CGFloat = 16

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [.pink.opacity(0.55), .indigo.opacity(0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "music.note")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .task(id: artworkPNG) {
            image = artworkPNG.flatMap { UIImage(data: $0) }
        }
    }
}

// MARK: - 來源標籤

struct SourceBadge: View {
    let source: MusicSource?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(source?.displayName ?? "待機中")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.secondary)
    }

    private var iconName: String {
        switch source {
        case .appleMusic: return "music.note"
        case .spotify: return "music.note.list"
        case .recognition: return "waveform"
        case nil: return "pause.circle"
        }
    }
}

// MARK: - 狀態膠囊

struct StatusCapsule: View {
    let text: String
    // 注意:預設值不可用 .secondary(那是 ShapeStyle,不是 Color)
    var tint: Color = .gray

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - 單行雙語歌詞

/// 雙語歌詞行(全螢幕與懸浮窗共用)。
struct BilingualLineView: View {
    let text: String
    let translation: String?
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 22, weight: isActive ? .bold : .medium))
                .foregroundStyle(isActive ? .primary : .secondary)
            if let translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                    // Color.primary/.secondary 為 Color 成員,可安全 .opacity(避免 ShapeStyle 不透明型別在三元運算中無法統一)
                    .foregroundStyle(isActive ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.7))
            }
        }
        .opacity(isActive ? 1 : 0.6)
        .scaleEffect(isActive ? 1.06 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isActive)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - 播放位置列

struct PlaybackProgressView: View {
    let position: TimeInterval
    let duration: TimeInterval

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.pink, .indigo],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: duration > 0
                               ? proxy.size.width * CGFloat(min(position / duration, 1))
                               : 0)
                }
            }
            .frame(height: 6)
            HStack {
                Text(Self.format(position))
                Spacer()
                Text(duration > 0 ? Self.format(duration) : "--:--")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    static func format(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let total = Int(time)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
