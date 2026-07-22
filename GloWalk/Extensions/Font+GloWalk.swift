import SwiftUI

extension Font {
    // LXGW WenKai — ancient-book style Chinese font
    static let gloWenKaiLight    = Font.custom("LXGW WenKai", size: 14)       // available via Light variant
    static let gloWenKaiRegular  = Font.custom("LXGW WenKai", size: 14)
    static let gloWenKaiMedium   = Font.custom("LXGW WenKai Medium", size: 14)

    // Monospace variant — for stats/numbers
    static let gloWenKaiMonoLight = Font.custom("LXGW WenKai Mono", size: 14)

    // Semantic helpers
    static func gloDisplay(_ size: CGFloat) -> Font {
        .custom("LXGW WenKai Light", size: size)
    }
    static func gloBody(_ size: CGFloat = 14) -> Font {
        .custom("LXGW WenKai", size: size)
    }
    static func gloHeadline(_ size: CGFloat = 17) -> Font {
        .custom("LXGW WenKai Medium", size: size)
    }
    static func gloMono(_ size: CGFloat = 12) -> Font {
        .custom("LXGW WenKai Mono", size: size)
    }
}
