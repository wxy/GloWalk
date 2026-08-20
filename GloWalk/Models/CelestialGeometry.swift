import CoreGraphics

/// Shared geometry for the sun/moon backdrop disc in the HUD and the poster,
/// so both surfaces show the celestial body at the same relative size (and the
/// sun and moon share one look).
///
/// The disc used to be 1.6× the surface width with its center far off-screen,
/// which left only a sliver of the moon's limb visible — at that crop a full
/// moon and a half moon were indistinguishable. The current disc is 1.0× the
/// surface width, centered just off the top-left corner, so roughly half the
/// disc is visible: the terminator is readable (full vs half vs crescent)
/// while it stays a decorative corner element, not a full centered moon.
enum CelestialGeometry {
    /// Disc radius as a fraction of the surface width (HUD points / poster pixels).
    static let radiusFactor: CGFloat = 0.5
    /// Center offset as a fraction of the radius (negative = up/left).
    static let centerXFactor: CGFloat = -0.10
    static let centerYFactor: CGFloat = -0.05
}
