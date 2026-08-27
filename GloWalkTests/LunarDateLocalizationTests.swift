import XCTest
@testable import GloWalk

final class LunarDateLocalizationTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15

    override func tearDown() {
        UserDefaults.standard.set("system", forKey: "language")
        super.tearDown()
    }

    func testJapaneseLunarDisplay() {
        UserDefaults.standard.set("ja", forKey: "language")
        let out = LunarDate.display(for: reference)
        XCTAssertTrue(out.hasPrefix("旧暦"), "expected 旧暦 prefix, got \(out)")
        XCTAssertTrue(out.hasSuffix("日"), "expected day suffix 日, got \(out)")
        XCTAssertFalse(out.contains("Lunar"), "must not fall back to English, got \(out)")
    }

    func testKoreanLunarDisplay() {
        UserDefaults.standard.set("ko", forKey: "language")
        let out = LunarDate.display(for: reference)
        XCTAssertTrue(out.hasPrefix("음력 "), "expected 음력 prefix, got \(out)")
        XCTAssertTrue(out.contains("월") && out.contains("일"), "expected 월/일, got \(out)")
        XCTAssertFalse(out.contains("Lunar"), "must not fall back to English, got \(out)")
    }

    func testJapaneseGregorianShort() {
        UserDefaults.standard.set("ja", forKey: "language")
        let out = LunarDate.gregorianShort(for: reference)
        XCTAssertTrue(out.contains("月") && out.contains("日"), "expected M月d日, got \(out)")
    }

    func testKoreanGregorianShort() {
        UserDefaults.standard.set("ko", forKey: "language")
        let out = LunarDate.gregorianShort(for: reference)
        XCTAssertTrue(out.contains("월") && out.contains("일"), "expected M월 d일, got \(out)")
    }
}
