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
/// [建置修正] `CPListItem.text / detailText` 為唯讀 —— 更新內容時需
/// **重建 items 陣列並以 `CPListTemplate.updateSections(_:)` 替換**。
/// `CPTemplateApplicationSceneDelegate` 連線回呼有兩組變體
/// (音訊類 App 走 `didConnect:` 無 window 版),兩組皆實作確保相容。
@MainActor
final class CarPlaySceneDelegate: NSObject, @preconcurrency CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?
    private var lyricsTemplate: CPListTemplate?

    /// 固定顯示 1(當前)+ 6(後續)行
    private static let previewLineCount = 6

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

        // 建立根模板(初始為空狀態),內容隨後由 updateLines 填入
        let template = CPListTemplate(
            title: CarPlayLyricsBridge.shared.currentTrack?.title ?? "LyricFlow 歌詞",
            sections: [CPListSection(items: [CPListItem(text: "搜尋歌詞中…", detailText: nil)])]
        )
        lyricsTemplate = template
        interfaceController.setRootTemplate(template, animated: true, completion: nil)

        updateLines(
            index: nil,
            text: nil,
            translation: nil,
            nextText: nil,
            lyrics: CarPlayLyricsBridge.shared.currentLyrics
        )
    }

    private func detach() {
        interfaceController = nil
        lyricsTemplate = nil
        if CarPlayLyricsBridge.shared.sceneDelegate === self {
            CarPlayLyricsBridge.shared.sceneDelegate = nil
        }
    }

    // MARK: - 內容更新(由 CarPlayLyricsBridge 呼叫)

    /// 換歌時呼叫:重建列表內容。
    /// (模板標題在 attach 時固定,CPListTemplate.title 的可寫性不確定故不觸碰)
    func rebuildForTrack(track: Track?, lyrics: LyricsDocument?) {
        updateLines(index: nil, text: nil, translation: nil, nextText: nil, lyrics: lyrics)
    }

    /// 歌詞行推進時呼叫:重建 items 並以 updateSections 送回模板。
    func updateLines(index: Int?, text: String?, translation: String?, nextText: String?, lyrics: LyricsDocument?) {
        guard let template = lyricsTemplate else { return }

        let items = Self.makeItems(
            index: index,
            text: text,
            translation: translation,
            lyrics: lyrics,
            track: CarPlayLyricsBridge.shared.currentTrack
        )
        template.updateSections([CPListSection(items: items)])
    }

    func updatePlaybackState(isPlaying: Bool) {
        // 播放狀態目前僅供橋接器記錄;畫面無需動作
    }

    // MARK: - items 建構

    private static func makeItems(
        index: Int?,
        text: String?,
        translation: String?,
        lyrics: LyricsDocument?,
        track: Track?
    ) -> [CPListItem] {
        // 無曲目 → 空狀態
        guard let track else {
            return [
                CPListItem(text: "未偵測到播放中的音樂",
                           detailText: "請在 iPhone 上開始播放 Apple Music 或 Spotify"),
            ]
        }

        // 有曲目但尚無歌詞 → 搜尋提示
        guard let lyrics else {
            return [
                CPListItem(text: "搜尋歌詞中…", detailText: "\(track.title) — \(track.artist)"),
            ]
        }

        // 純文字歌詞 → 提示無同步
        guard let index, let text, lyrics.isSynced else {
            if lyrics.isSynced {
                return [CPListItem(text: "♪", detailText: "\(track.title) — \(track.artist)")]
            }
            return [CPListItem(text: "此曲僅提供純文字歌詞", detailText: "\(track.title) — \(track.artist)")]
        }

        // 當前行(原文 + 譯文)
        var items = [CPListItem(text: text, detailText: (translation?.isEmpty == true) ? nil : translation)]

        // 後續 6 行預覽
        let allLines = lyrics.lines
        for offset in 1...Self.previewLineCount {
            let lineIndex = index + offset
            if lineIndex < allLines.count {
                items.append(CPListItem(text: allLines[lineIndex].text, detailText: nil))
            }
        }
        return items
    }
}
