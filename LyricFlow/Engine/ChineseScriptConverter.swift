import Foundation
import NaturalLanguage

/// 簡體中文 → 繁體中文轉換。
///
/// 歌詞來源(Musixmatch / 網易雲 / LRCLIB)對華語歌曲常回傳簡體中文;
/// 本工具在歌詞進入快取與顯示前,把簡體原文(與官方譯文)轉成繁體。
///
/// 以 ICU transform `Simplified-Traditional` 逐字轉換,並以 `NLLanguageRecognizer`
/// 先判斷是否為簡體中文 —— 避免誤傷與簡體同形的日本漢字(如「国」「学」)。
public enum ChineseScriptConverter {

    /// ICU 簡體 → 繁體轉譯器。
    private static let simplifiedToTraditional = StringTransform(rawValue: "Simplified-Traditional")

    /// 將整份歌詞(原文 + 逐行譯文)中的簡體中文轉為繁體。
    public static func convert(_ document: LyricsDocument) -> LyricsDocument {
        var converted = document

        // 原文:整首判定為簡體中文才逐行轉換
        let originalText = document.lines.map(\.text).joined(separator: "\n")
        if isSimplifiedChinese(originalText) {
            converted.lines = document.lines.map { line in
                LyricLine(
                    index: line.index,
                    text: toTraditional(line.text),
                    startTime: line.startTime,
                    endTime: line.endTime
                )
            }
        }

        // 譯文:官方翻譯(如網易雲 tlyric)亦可能是簡體
        let translationText = document.translations.values.joined(separator: "\n")
        if !translationText.isEmpty, isSimplifiedChinese(translationText) {
            converted.translations = document.translations.mapValues(toTraditional)
        }

        return converted
    }

    /// 判斷文字是否以簡體中文為主。
    ///
    /// 僅在明確偵測為簡體中文(`zh-Hans`)時回傳 true;
    /// 繁體、日文或無法判定(僅回傳 `zh`)一律回傳 false,確保不會誤轉。
    public static func isSimplifiedChinese(_ text: String) -> Bool {
        let sample = String(text.prefix(2000))
        guard !sample.isEmpty else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        return recognizer.dominantLanguage == .simplifiedChinese
    }

    /// 逐字將簡體轉為繁體;轉換器不可用時原樣回傳。
    public static func toTraditional(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.applyingTransform(simplifiedToTraditional, reverse: false) ?? text
    }
}
