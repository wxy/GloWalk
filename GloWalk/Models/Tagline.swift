import Foundation

struct TaglineItem: Codable, Identifiable {
    var id: String { key }
    let key: String
    let phrase: String
    let phrase_en: String
    let explanation: String
    let explanation_en: String

    /// Returns the phrase in the current system language
    var localizedPhrase: String {
        isChinese ? phrase : phrase_en
    }
    var localizedExplanation: String {
        isChinese ? explanation : explanation_en
    }

    private var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }
}

enum Tagline {
    static var pool: [TaglineItem] = {
        guard let url = Bundle.main.url(forResource: "Taglines", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[Tagline] Failed to load Taglines.json from bundle")
            return fallbackPool
        }
        do {
            let items = try JSONDecoder().decode([TaglineItem].self, from: data)
            print("[Tagline] Loaded \(items.count) taglines")
            return items
        } catch {
            print("[Tagline] JSON decode error: \(error)")
            return fallbackPool
        }
    }()

    private static let fallbackPool = [
        TaglineItem(key: "fallback", phrase: "踽踽独行，脚下有光",
                    phrase_en: "A solitary step, a lantern aglow",
                    explanation: "GloWalk 随行路灯",
                    explanation_en: "GloWalk — your night companion")
    ]

    static func random() -> TaglineItem {
        pool.randomElement() ?? TaglineItem(key: "fallback", phrase: "踽踽独行，脚下有光",
                                            phrase_en: "A solitary step, a lantern aglow",
                                            explanation: "GloWalk 随行路灯",
                                            explanation_en: "GloWalk — your night companion")
    }
}
