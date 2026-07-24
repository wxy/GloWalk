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
        .custom("LXGW WenKai Mono", size: size)
    }
}
