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
/// [建置修正] `CPTemplateApplicationSceneDelegate` 的連線回呼有兩組變體:
/// - 音訊類 App:`templateApplicationScene(_:didConnect:)` / `(_:didDisconnectInterfaceController:)`
/// - 導航類 App:`templateApplicationScene(_:didConnect:to:)` / `(_:didDisconnect:from:)`
/// 本 App 屬音訊類,系統呼叫前者;兩組都實作以確保相容。
/// 每行更新直接改動 `CPListItem` 的屬性,CarPlay 會自動刷新對應列(CPListItem 為 mutable)。
@MainActor
final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var lyricsTemplate: CPListTemplate?

    /// 固定顯示 1(當前)+ 6(後續)行
    private static let previewLineCount = 6
    private var lineItems: [CPListItem] = []

    // MARK: - 場景生命週期(音訊 App 變體 —— 本 App 實際走這裡)

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        attach(interfaceController: interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        detach()
    }

    // MARK: - 場景生命週期(導航 App 變體 —— 一併實作確保相容)

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        attach(interfaceController: interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        detach()
    }

    // MARK: - 連接 / 斷開

    private func attach(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        CarPlayLyricsBridge.shared.sceneDelegate = self
        rebuildForTrack(
            track: CarPlayLyricsBridge.shared.currentTrack,
            lyrics: CarPlayLyricsBridge.shared.currentLyrics
        )
    }

    private func detach() {
        interfaceController = nil
        lyricsTemplate = nil
        lineItems = []
        if CarPlayLyricsBridge.shared.sceneDelegate === self {
            CarPlayLyricsBridge.shared.sceneDelegate = nil
        }
    }

    // MARK: - 內容更新(由 CarPlayLyricsBridge 呼叫)

    func rebuildForTrack(track: Track?, lyrics: LyricsDocument?) {
        guard let interfaceController else { return }

        let items = (0...Self.previewLineCount).map { _ in
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

    func updateLines(index: Int?, text: String?, translation: String?, nextText: String?, lyrics: LyricsDocument?) {
        guard !lineItems.isEmpty else { return }

        guard let index, let text else {
            applyEmptyState(track: CarPlayLyricsBridge.shared.currentTrack, lyrics: lyrics)
            return
        }

        // 第 0 項:當前行(原文 + 譯文)
        lineItems[0].text = text
        lineItems[0].detailText = (translation?.isEmpty == true) ? nil : translation

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

    func updatePlaybackState(isPlaying: Bool) {
        // 播放狀態目前僅供橋接器記錄;畫面無需動作
    }

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
