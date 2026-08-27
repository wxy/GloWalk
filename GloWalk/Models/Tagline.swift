import Foundation

struct TaglineItem: Codable, Identifiable {
    var id: String { key }
    let key: String
    let phrase: String
    let phrase_ht: String
    let phrase_en: String
    // Tier-1/Tier-2 languages; optional so the fallback pool and any older
    // JSON stay decodable (resolution falls back to English).
    var phrase_ja: String?
    var phrase_ko: String?
    var phrase_fr: String?
    var phrase_de: String?
    var phrase_es: String?
    var phrase_pt: String?
    var phrase_it: String?
    var phrase_ru: String?
    let explanation: String
    let explanation_ht: String
    let explanation_en: String
    var explanation_ja: String?
    var explanation_ko: String?
    var explanation_fr: String?
    var explanation_de: String?
    var explanation_es: String?
    var explanation_pt: String?
    var explanation_it: String?
    var explanation_ru: String?

    /// Returns the phrase in the current language (simplified / traditional / English).
    var localizedPhrase: String {
        switch L10n.languageCode {
        case "zh-Hant": return phrase_ht
        case "zh-Hans": return phrase
        case "ja": return phrase_ja ?? phrase_en
        case "ko": return phrase_ko ?? phrase_en
        case "fr": return phrase_fr ?? phrase_en
        case "de": return phrase_de ?? phrase_en
        case "es": return phrase_es ?? phrase_en
        case "pt-BR": return phrase_pt ?? phrase_en
        case "it": return phrase_it ?? phrase_en
        case "ru": return phrase_ru ?? phrase_en
        default: return phrase_en
        }
    }
    var localizedExplanation: String {
        switch L10n.languageCode {
        case "zh-Hant": return explanation_ht
        case "zh-Hans": return explanation
        case "ja": return explanation_ja ?? explanation_en
        case "ko": return explanation_ko ?? explanation_en
        case "fr": return explanation_fr ?? explanation_en
        case "de": return explanation_de ?? explanation_en
        case "es": return explanation_es ?? explanation_en
        case "pt-BR": return explanation_pt ?? explanation_en
        case "it": return explanation_it ?? explanation_en
        case "ru": return explanation_ru ?? explanation_en
        default: return explanation_en
        }
    }
}

enum Tagline {
    static var pool: [TaglineItem] = {
        guard let url = Bundle.main.url(forResource: "Taglines", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            Log.error("[Tagline] Failed to load Taglines.json from bundle")
            return fallbackPool
        }
        do {
            let items = try JSONDecoder().decode([TaglineItem].self, from: data)
            Log.debug("[Tagline] Loaded \(items.count) taglines")
            return items
        } catch {
            Log.error("[Tagline] JSON decode error: \(error)")
            return fallbackPool
        }
    }()

    private static let fallbackPool = [
        TaglineItem(key: "fallback",
                    phrase: "踽踽独行，脚下有光",
                    phrase_ht: "踽踽獨行，腳下有光",
                    phrase_en: "A solitary step, a lantern aglow",
                    explanation: "GloWalk 随行路灯",
                    explanation_ht: "GloWalk 隨行路燈",
                    explanation_en: "GloWalk — your night companion")
    ]

    static func random() -> TaglineItem {
        pool.randomElement() ?? TaglineItem(key: "fallback",
                                            phrase: "踽踽独行，脚下有光",
                                            phrase_ht: "踽踽獨行，腳下有光",
                                            phrase_en: "A solitary step, a lantern aglow",
                                            explanation: "GloWalk 随行路灯",
                                            explanation_ht: "GloWalk 隨行路燈",
                                            explanation_en: "GloWalk — your night companion")
    }
}
