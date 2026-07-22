import Foundation

/// Simple lunar calendar date using iOS Chinese calendar.
enum LunarDate {
    static let chineseCalendar = Calendar(identifier: .chinese)
    static let gregorianCalendar = Calendar(identifier: .gregorian)

    static let monthNames = [
        "", "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]
    static let enMonths = [
        "", "Lunar Jan", "Lunar Feb", "Lunar Mar", "Lunar Apr",
        "Lunar May", "Lunar Jun", "Lunar Jul", "Lunar Aug",
        "Lunar Sep", "Lunar Oct", "Lunar Nov", "Lunar Dec"
    ]
    static let dayNames = [
        "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    /// Chinese display: "六月十五"
    static func chineseDisplay(for date: Date = Date()) -> String {
        let comps = chineseCalendar.dateComponents([.month, .day], from: date)
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let monthStr = (m > 0 && m <= 12) ? monthNames[m] : ""
        let dayStr = (d > 0 && d <= 30) ? dayNames[d] : ""
        return "\(monthStr)\(dayStr)"
    }

    /// English display: "Lunar Jun 15"
    static func englishDisplay(for date: Date = Date()) -> String {
        let comps = chineseCalendar.dateComponents([.month, .day], from: date)
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let monthStr = (m > 0 && m <= 12) ? enMonths[m] : ""
        return "\(monthStr) \(d)"
    }

    /// Auto-select based on current locale
    static func display(for date: Date = Date()) -> String {
        let lang = Locale.preferredLanguages.first ?? "en"
        if lang.hasPrefix("zh") {
            return chineseDisplay(for: date)
        } else {
            return englishDisplay(for: date)
        }
    }

    /// Short gregorian date: "7/22" in en, "7月22日" in zh
    static func gregorianShort(for date: Date = Date()) -> String {
        let lang = Locale.preferredLanguages.first ?? "en"
        let df = DateFormatter()
        if lang.hasPrefix("zh") {
            df.dateFormat = "M月d日"
        } else {
            df.dateFormat = "M/d"
        }
        return df.string(from: date)
    }
}
