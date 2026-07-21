import SwiftUI

extension Color {
    // Amber family
    static let gloTorchCore    = Color(red: 1.00, green: 0.953, blue: 0.878)
    static let gloTorchInner   = Color(red: 1.00, green: 0.878, blue: 0.698)
    static let gloTorchGlow    = Color(red: 1.00, green: 0.800, blue: 0.502)
    static let gloAmber        = Color(red: 1.00, green: 0.718, blue: 0.302)
    static let gloAmberDeep    = Color(red: 1.00, green: 0.655, blue: 0.149)
    static let gloAmberDark    = Color(red: 1.00, green: 0.561, blue: 0.000)
    static let gloAmberDim     = Color(red: 0.60, green: 0.416, blue: 0.000)

    // Blacks
    static let gloBlack        = Color(red: 0, green: 0, blue: 0)
    static let gloBlackCard    = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let gloBlackSurface = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let gloBlackBorder  = Color(red: 0.149, green: 0.149, blue: 0.149)
    static let gloBlackInset   = Color(red: 0.200, green: 0.200, blue: 0.200)

    // Opacity helpers
    static func gloAmber(opacity: Double) -> Color {
        Color.gloAmber.opacity(opacity)
    }
    static func gloWhite(opacity: Double) -> Color {
        Color.white.opacity(opacity)
    }
}
