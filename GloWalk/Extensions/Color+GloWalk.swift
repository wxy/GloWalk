import SwiftUI

extension Color {
    // Dark gold family — antique brass/lantern glow
    static let gloGold      = Color(red: 0.769, green: 0.643, blue: 0.290)  // #C4A44A  dark gold (main accent)
    static let gloAmber     = gloGold  // amber alias

    // Torch glow — pale gold (lantern paper)
    static let gloTorchCore = Color(red: 0.961, green: 0.902, blue: 0.784)  // #F5E6C8  pale gold glow

    // Blacks
    static let gloBlack        = Color(red: 0, green: 0, blue: 0)
    static let gloBlackCard    = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let gloBlackSurface = Color(red: 0.102, green: 0.102, blue: 0.102)

    // Factor colors — shared between the HUD rings' deduction segments and the
    // factor-row dots, so the two stay visually linked.
    static let gloFactorAmbient  = Color(red: 0.95, green: 0.40, blue: 0.40)
    static let gloFactorPosture  = Color(red: 0.35, green: 0.65, blue: 1.0)
    static let gloFactorDark     = Color(red: 0.75, green: 0.45, blue: 1.0)
    static let gloFactorMoon     = Color(red: 1.0, green: 0.80, blue: 0.30)
    static let gloFactorWeather  = Color(red: 0.30, green: 0.90, blue: 0.90)
    /// Ordered ambient/posture/dark/moon/weather — matches factorShares order.
    static let gloFactorPalette: [Color] = [
        gloFactorAmbient, gloFactorPosture,
        gloFactorDark, gloFactorMoon, gloFactorWeather
    ]
}
