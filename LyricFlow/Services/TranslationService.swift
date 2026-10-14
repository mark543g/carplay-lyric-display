import Foundation
import Translation
import NaturalLanguage

/// 智慧翻譯服務:以 Apple Translation 框架離線逐行翻譯歌詞。
///
/// 兩種取得 TranslationSession 的途徑:
/// 1. 無 UI 的批次翻譯:`TranslationSession(installedSource:target:)` —— 語言模型必須已安裝,
///    否則拋出錯誤並回報 `needsBootstrap` 狀態。
/// 2. 語言模型下載 bootstrap:由設定頁掛上 `.translationTask` 修飾器,
///    在 session 回呼中呼叫 `prepareTranslation()` 觸發下載。
@MainActor
final class TranslationService: ObservableObject {

    static let shared = TranslationService()

    enum State: Equatable {
        case idle
        case translating
        case done
        case notNeeded        // 原文即目標語言
        case failed(String)
        case needsBootstrap(source: String, target: String)
    }

    @Published var state: State = .idle

    enum TranslationError: LocalizedError {
        case languagesNotInstalled(source: String, target: String)
        case emptyInput
        case sessionFailure(String)

        var errorDescription: String? {
            switch self {
            case .languagesNotInstalled:
                return "翻譯語言模型尚未下載,請至「設定 → 翻譯語言」先準備模型"
            case .emptyInput:
                return "沒有可翻譯的歌詞內容"
            case .sessionFailure(let message):
                return "翻譯失敗:\(message)"
            }
        }
    }

    /// 常用翻譯目標語言。
    static let supportedLanguages: [(code: String, name: String)] = [
        ("zh-Hant", "繁體中文"),
        ("zh-Hans", "简体中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("it", "Italiano"),
        ("pt", "Português"),
        ("ru", "Русский"),
        ("ar", "العربية"),
        ("hi", "हिन्दी"),
        ("th", "ไทย"),
        ("vi", "Tiếng Việt"),
        ("id", "Bahasa Indonesia"),
        ("tr", "Türkçe"),
    ]

    // MARK: - 語言偵測

    /// 以 NaturalLanguage 偵測歌詞原語言,回傳 BCP-47 代碼(如 "en"、"zh-Hant")。
    func detectLanguage(of text: String) -> String? {
        let sample = String(text.prefix(2000))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        // NLLanguage rawValue 即 BCP-47 代碼
        let code = dominant.rawValue
        // NLLanguage 的中文分為 zh-Hans / zh-Hant;其餘直接回傳
        return code
    }

    // MARK: - 主要流程

    /// 逐行翻譯整份歌詞。回傳 lineIndex → 譯文。
    func translate(document: LyricsDocument, targetLanguage: String) async -> [Int: String] {
        let texts = document.lines.map(\.text)
        guard !texts.isEmpty else {
            state = .failed(TranslationError.emptyInput.localizedDescription)
            return [:]
        }

        // 偵測原語言
        let sourceCode = detectLanguage(of: texts.joined(separator: "\n")) ?? "en"
        if sourceCode == targetLanguage {
            state = .notNeeded
            return [:]
        }

        // 命中快取
        if let cached = SharedStore.loadTranslations(trackID: document.trackID, language: targetLanguage) {
            state = .done
            var result: [Int: String] = [:]
            for (key, value) in cached {
                if let index = Int(key) { result[index] = value }
            }
            return result
        }

        state = .translating
        do {
            let source = Locale.Language(identifier: sourceCode)
            let target = Locale.Language(identifier: targetLanguage)
            let translated = try await translateBatch(
                texts: texts,
                source: source,
                target: target,
                sourceCode: sourceCode,
                targetCode: targetLanguage
            )

            // 寫入快取
            var cache: [String: String] = [:]
            var result: [Int: String] = [:]
            for (index, text) in translated.enumerated() {
                cache[String(index)] = text
                result[index] = text
            }
            SharedStore.saveTranslations(cache, trackID: document.trackID, language: targetLanguage)
            state = .done
            return result
        } catch let error as TranslationError {
            if case .languagesNotInstalled(let source, let target) = error {
                state = .needsBootstrap(source: source, target: target)
            } else {
                state = .failed(error.localizedDescription)
            }
            return [:]
        } catch {
            state = .failed(error.localizedDescription)
            return [:]
        }
    }

    /// 批次翻譯(內部分批,每批 64 行,避免單次 session 過大)。
    private func translateBatch(
        texts: [String],
        source: Locale.Language,
        target: Locale.Language,
        sourceCode: String,
        targetCode: String
    ) async throws -> [String] {
        let session: TranslationSession
        do {
            session = try TranslationSession(installedSource: source, target: target)
        } catch {
            // 報告用的代碼直接由呼叫端傳入(Locale.Language 無 identifier 成員)
            throw TranslationError.languagesNotInstalled(source: sourceCode, target: targetCode)
        }

        var results: [String] = []
        results.reserveCapacity(texts.count)
        let chunkSize = 64
        var start = 0
        while start < texts.count {
            let end = min(start + chunkSize, texts.count)
            let chunk = Array(texts[start..<end])
            let requests = chunk.enumerated().map { offset, text in
                TranslationSession.Request(sourceText: text, clientIdentifier: String(start + offset))
            }
            let responses = try await session.translations(from: requests)
            // 依 clientIdentifier 還原順序
            let ordered = responses.sorted { lhs, rhs in
                let l = Int(lhs.clientIdentifier ?? "-1") ?? -1
                let r = Int(rhs.clientIdentifier ?? "-1") ?? -1
                return l < r
            }
            results.append(contentsOf: ordered.map(\.targetText))
            start = end
        }
        return results
    }
}
