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
    /// Traditional Japanese lunar month names (旧暦の月名).
    static let jaMonths = [
        "", "睦月", "如月", "弥生", "卯月", "皐月", "水無月",
        "文月", "葉月", "長月", "神無月", "霜月", "師走"
    ]
    /// Korean lunar months (음력), e.g. "1월" … "12월".
    static let koMonths = [
        "", "1월", "2월", "3월", "4월", "5월", "6월",
        "7월", "8월", "9월", "10월", "11월", "12월"
    ]
    static let dayNames = [
        "", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]
    /// Japanese lunar day names, e.g. "一日" … "三十日".
    static let jaDays = [
        "", "一日", "二日", "三日", "四日", "五日", "六日", "七日", "八日", "九日", "十日",
        "十一日", "十二日", "十三日", "十四日", "十五日", "十六日", "十七日", "十八日", "十九日", "二十日",
        "二十一日", "二十二日", "二十三日", "二十四日", "二十五日", "二十六日", "二十七日", "二十八日", "二十九日", "三十日"
    ]
    /// Korean lunar day names, e.g. "1일" … "30일".
    static let koDays = [
        "", "1일", "2일", "3일", "4일", "5일", "6일", "7일", "8일", "9일", "10일",
        "11일", "12일", "13일", "14일", "15일", "16일", "17일", "18일", "19일", "20일",
        "21일", "22일", "23일", "24일", "25일", "26일", "27일", "28일", "29일", "30일"
    ]
    /// Cached formatters — DateFormatter creation is expensive, and this is
    /// called once per second while the HUD is walking.
    private static let zhShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "zh-Hans")
        df.dateFormat = "M月d日"
        return df
    }()
    private static let enShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "M/d"
        return df
    }()
    private static let jaShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "M月d日"
        return df
    }()
    private static let koShortFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "M월 d일"
        return df
    }()

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

    /// Japanese display: "旧暦睦月十五日"
    static func japaneseDisplay(for date: Date = Date()) -> String {
        let comps = chineseCalendar.dateComponents([.month, .day], from: date)
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let monthStr = (m > 0 && m <= 12) ? jaMonths[m] : ""
        let dayStr = (d > 0 && d <= 30) ? jaDays[d] : ""
        return "旧暦\(monthStr)\(dayStr)"
    }

    /// Korean display: "음력 6월 15일"
    static func koreanDisplay(for date: Date = Date()) -> String {
        let comps = chineseCalendar.dateComponents([.month, .day], from: date)
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let monthStr = (m > 0 && m <= 12) ? koMonths[m] : ""
        let dayStr = (d > 0 && d <= 30) ? koDays[d] : ""
        return "음력 \(monthStr) \(dayStr)"
    }

    /// Auto-select based on language preference
    static func display(for date: Date = Date()) -> String {
        switch L10n.languageCode {
        case "ja": return japaneseDisplay(for: date)
        case "ko": return koreanDisplay(for: date)
        default:
            if L10n.isZh {
                return chineseDisplay(for: date)
            }
            return englishDisplay(for: date)
        }
    }

    /// Short gregorian date: "M/d" in en, "M月d日" in zh/ja, "M월 d일" in ko
    static func gregorianShort(for date: Date = Date()) -> String {
        switch L10n.languageCode {
        case "ja": return jaShortFormatter.string(from: date)
        case "ko": return koShortFormatter.string(from: date)
        default:
            return L10n.isZh ? zhShortFormatter.string(from: date)
                             : enShortFormatter.string(from: date)
        }
    }
}
