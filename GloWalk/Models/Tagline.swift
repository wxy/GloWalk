import Foundation

struct TaglineItem: Codable, Identifiable {
    var id: String { phrase }
    let phrase: String
    let explanation: String
}

enum Tagline {
    static var pool: [TaglineItem] = {
        guard let url = Bundle.main.url(forResource: "Taglines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([TaglineItem].self, from: data) else {
            return [TaglineItem(phrase: "踽踽独行，脚下有光", explanation: "GloWalk 随行路灯")]
        }
        return items
    }()

    static func random() -> TaglineItem {
        pool.randomElement() ?? TaglineItem(phrase: "踽踽独行，脚下有光", explanation: "GloWalk 随行路灯")
    }
}
