import UIKit

enum Haptic {
    // Generators are cheap to create but intended to be reused; creating a new
    // one per call defeats their internal preparation and adds needless work
    // on hot paths (every brightness drag tick).
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func light() {
        lightGenerator.impactOccurred()
    }
    static func medium() {
        mediumGenerator.impactOccurred()
    }
    static func heavy() {
        heavyGenerator.impactOccurred()
    }
    static func selection() {
        selectionGenerator.selectionChanged()
    }
}
