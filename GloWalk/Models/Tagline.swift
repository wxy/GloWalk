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

    /// Product voice used before or outside a completed walk. Past-tense
    /// keepsake copy must never leak into the splash screen or Settings.
    private static let brandKeys: Set<String> = [
        "tagline.moon", "tagline.streetlight", "tagline.adaptation", "tagline.rain",
        "tagline.pocket", "tagline.pupil", "tagline.battery", "tagline.arrival"
    ]

    /// Copy grounded in something that happened during the recorded walk.
    private static let nightMemoryKeys: Set<String> = [
        "tagline.moon", "tagline.streetlight", "tagline.adaptation", "tagline.rain",
        "tagline.resumed", "tagline.winding", "tagline.quiet"
    ]

    static var brandPool: [TaglineItem] {
        let items = pool.filter { brandKeys.contains($0.key) }
        return items.isEmpty ? fallbackPool : items
    }

    static var nightMemoryPool: [TaglineItem] {
        let items = pool.filter { item in
            nightMemoryKeys.contains { baseKey in
                item.key == baseKey || item.key.hasPrefix(baseKey + ".")
            }
        }
        return items.isEmpty ? fallbackPool : items
    }

    static func nightMemory(for profile: NightMemoryProfile, seed: UInt64,
                            excluding acquiredKeys: Set<String> = []) -> TaglineItem {
        nightMemory(key: profile.theme.taglineKey, seed: seed, excluding: acquiredKeys)
    }

    static func nightMemory(key: String, seed: UInt64,
                            excluding acquiredKeys: Set<String> = []) -> TaglineItem {
        let candidates = nightMemoryPool.filter {
            $0.key == key || $0.key.hasPrefix(key + ".")
        }.sorted { $0.key < $1.key }
        guard !candidates.isEmpty else { return fallbackPool[0] }
        let unacquired = candidates.filter { !acquiredKeys.contains($0.key) }
        // Complete the current theme before repeating a phrase. The walk facts
        // still choose the theme; this only makes its three equivalent poetic
        // variants fair to collect.
        let selectable = unacquired.isEmpty ? candidates : unacquired
        var random = NightMemoryRandom(seed: seed)
        return selectable[Int(random.next() % UInt64(selectable.count))]
    }

    /// Resolve an already persisted phrase exactly. Older records saved a base
    /// key before variants existed, so they continue to show their original
    /// sentence rather than being silently rerolled.
    static func savedNightMemory(key: String) -> TaglineItem? {
        nightMemoryPool.first { $0.key == key }
    }

    /// Stable brand line for a generated keepsake. Excluding the memory key
    /// prevents the same sentence from appearing twice when a line is valid in
    /// both curated collections.
    static func brand(seed: UInt64, excludingKey: String? = nil) -> TaglineItem {
        let distinct = brandPool.filter { $0.key != excludingKey }
        let candidates = distinct.isEmpty ? brandPool : distinct
        return candidates[Int(seed % UInt64(candidates.count))]
    }

    static func randomBrand() -> TaglineItem {
        brandPool.randomElement() ?? fallbackPool[0]
    }
}

/// A single lightweight unread signal. The collection itself remains derived
/// from walk records, so this never duplicates route, date, or achievement data.
enum NightMemoryDiscovery {
    static let unseenDefaultsKey = "hasUnseenNightMemory"

    static func markUnseen() {
        UserDefaults.standard.set(true, forKey: unseenDefaultsKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(false, forKey: unseenDefaultsKey)
    }
}
