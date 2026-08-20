import SwiftUI

extension Font {
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
        // The bundled Mono TTF's family name is "LXGW WenKai Mono Light" —
        // "LXGW WenKai Mono" does not resolve and silently fell back to the
        // system font for the HUD numbers.
        .custom("LXGW WenKai Mono Light", size: size)
    }
}
