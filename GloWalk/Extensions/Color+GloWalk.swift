import SwiftUI

extension Color {
    // Dark gold family — antique brass/lantern glow
    static let gloGoldCore    = Color(red: 0.961, green: 0.902, blue: 0.784)  // #F5E6C8  pale gold glow
    static let gloGoldInner   = Color(red: 0.910, green: 0.835, blue: 0.639)  // #E8D5A3  lantern paper inner
    static let gloGoldGlow    = Color(red: 0.831, green: 0.725, blue: 0.416)  // #D4B96A  polished brass
    static let gloGold        = Color(red: 0.769, green: 0.643, blue: 0.290)  // #C4A44A  dark gold (main accent)
    static let gloGoldDeep    = Color(red: 0.659, green: 0.533, blue: 0.196)  // #A88832  aged brass
    static let gloGoldDark    = Color(red: 0.545, green: 0.435, blue: 0.169)  // #8B6F2B  dark bronze
    static let gloGoldDim     = Color(red: 0.420, green: 0.329, blue: 0.125)  // #6B5420  deep patina

    // Legacy aliases (keep existing code working)
    static let gloTorchCore   = gloGoldCore
    static let gloTorchInner  = gloGoldInner
    static let gloTorchGlow   = gloGoldGlow
    static let gloAmber       = gloGold
    static let gloAmberDeep   = gloGoldDeep
    static let gloAmberDark   = gloGoldDark
    static let gloAmberDim    = gloGoldDim
    static let gloAmberLight  = gloGoldGlow

    // Blacks
    static let gloBlack        = Color(red: 0, green: 0, blue: 0)
    static let gloBlackCard    = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let gloBlackSurface = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let gloBlackBorder  = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let gloBlackInset   = Color(red: 0.200, green: 0.200, blue: 0.200)

    // Opacity helpers
    static func gloGold(opacity: Double) -> Color {
        Color.gloGold.opacity(opacity)
    }
    static func gloWhite(opacity: Double) -> Color {
        Color.white.opacity(opacity)
    }
}
