import XCTest
import UIKit

final class FontRegistrationTests: XCTestCase {
    /// The HUD/poster refer to the bundled WenKai faces by these names. If a
    /// name stops resolving (e.g. after a font re-subset), UIFont silently
    /// falls back to the system font, so pin the exact names here.
    func testBundledWenKaiFacesResolveByName() {
        let names = [
            "LXGW WenKai",
            "LXGW WenKai Light",
            "LXGW WenKai Medium",
            "LXGW WenKai Mono Light",
            "Klee One",
            "Klee One SemiBold",
            "LXGW WenKai KR",
            "LXGW WenKai KR Light",
            "LXGW WenKai KR Medium",
            "LXGW WenKai Mono KR Light",
        ]
        for name in names {
            XCTAssertNotNil(UIFont(name: name, size: 12),
                            "Font '\(name)' must resolve to the bundled TTF")
        }
    }
}
