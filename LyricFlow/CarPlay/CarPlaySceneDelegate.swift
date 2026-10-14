import Foundation
import CarPlay
import UIKit

/// CarPlay 傳統模板場景:在車機上顯示動態歌詞頁。
///
/// 透過 Info.plist 的 `UIApplicationSceneManifest` 註冊
/// `CPTemplateApplicationSceneSessionRoleApplication`,由系統在連車時建立。
///
/// 內容分兩層:
/// - 目前行:原文 + 譯文(CPListItem text / detailText)
/// - 接下來 6 行:預覽歌詞
///
/// 每行更新直接改動 `CPListItem` 的屬性,CarPlay 會自動刷新對應列
/// (CPListItem 為 mutable reference type)。
final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var lyricsTemplate: CPListTemplate?

    /// 固定顯示 1(當前)+ 6(後續)行
    private static let previewLineCount = 6
    private var lineItems: [CPListItem] = []

    // MARK: - 場景生命週期

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        self.interfaceController = interfaceController
        Task { @MainActor in
            CarPlayLyricsBridge.shared.sceneDelegate = self
            self.rebuildForTrack(
                track: CarPlayLyricsBridge.shared.currentTrack,
                lyrics: CarPlayLyricsBridge.shared.currentLyrics
            )
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        self.interfaceController = nil
        lyricsTemplate = nil
        lineItems = []
        Task { @MainActor in
            if CarPlayLyricsBridge.shared.sceneDelegate === self {
                CarPlayLyricsBridge.shared.sceneDelegate = nil
            }
        }
    }

    // MARK: - 內容更新(由 CarPlayLyricsBridge 主執行緒呼叫)

    @MainActor
    func rebuildForTrack(track: Track?, lyrics: LyricsDocument?) {
        guard let interfaceController else { return }

        let items = (0...(Self.previewLineCount)).map { _ in
            CPListItem(text: "", detailText: nil)
        }
        lineItems = items
        let section = CPListSection(items: items)
        let template = CPListTemplate(title: track?.title ?? "LyricFlow 歌詞", sections: [section])
        lyricsTemplate = template

        interfaceController.setRootTemplate(template, animated: true, completion: nil)
        updateLines(index: nil, text: nil, translation: nil, nextText: nil, lyrics: lyrics)
        applyEmptyState(track: track, lyrics: lyrics)
    }

    @MainActor
    func updateLines(index: Int?, text: String?, translation: String?, nextText: String?, lyrics: LyricsDocument?) {
        guard !lineItems.isEmpty else { return }

        guard let index, let text else {
            applyEmptyState(track: CarPlayLyricsBridge.shared.currentTrack, lyrics: lyrics)
            return
        }

        // 第 0 项:當前行(原文 + 譯文)
        lineItems[0].text = text
        lineItems[0].detailText = translation?.isEmpty == true ? nil : translation

        // 後續 6 行:預覽
        let allLines = lyrics?.lines ?? []
        for offset in 0..<Self.previewLineCount {
            let itemIndex = offset + 1
            let lineIndex = index + offset + 1
            if lineIndex < allLines.count {
                lineItems[itemIndex].text = allLines[lineIndex].text
                lineItems[itemIndex].detailText = nil
            } else {
                lineItems[itemIndex].text = ""
                lineItems[itemIndex].detailText = nil
            }
        }
    }

    @MainActor
    func updatePlaybackState(isPlaying: Bool) {
        // 播放狀態主要影響標題列的提示文字;目前無需動作。
    }

    @MainActor
    private func applyEmptyState(track: Track?, lyrics: LyricsDocument?) {
        guard let first = lineItems.first else { return }
        if track == nil {
            first.text = "未偵測到播放中的音樂"
            first.detailText = "請在 iPhone 上開始播放 Apple Music 或 Spotify"
            for item in lineItems.dropFirst() {
                item.text = ""
                item.detailText = nil
            }
        } else if lyrics == nil {
            first.text = "搜尋歌詞中…"
            first.detailText = track.map { "\($0.title) — \($0.artist)" }
            for item in lineItems.dropFirst() {
                item.text = ""
                item.detailText = nil
            }
        } else if lyrics?.isSynced == false {
            first.text = "此曲僅提供純文字歌詞"
            first.detailText = track.map { "\($0.title) — \($0.artist)" }
        }
    }
}
