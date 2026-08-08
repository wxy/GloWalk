import SwiftUI

struct GlowCircleView: View {
    let brightness: Double
    let screenBrightness: Double
    /// Factor shortfall proportions (ambient/posture/dark/moon/weather, sum 1)
    /// — colors the unfilled ring segments that the factors "deduct".
    let factorShares: [Double]
    let isManual: Bool
    let cadence: Double
    let isPaused: Bool

    @State private var breathe: Double = 0
    @State private var stepPhase: Double = 0

    private var warmth: Double { brightness }

    /// Icon opacity scales with brightness:
    /// dim torch → ghost outline; full torch → clearly visible brand mark.
    private var iconOpacity: Double { 0.20 + warmth * 0.70 }

    private var torchSegments: Int {
        min(max(Int((brightness * 10).rounded()), 0), 10)
    }
    private var screenSegments: Int {
        min(max(Int((screenBrightness * 10).rounded()), 0), 10)
    }

    var body: some View {
        ZStack {
            // Layer 0: App icon — the central visual element.
            // The icon already has a grainy glow texture, so it replaces
            // the inner core glow and serves as the lantern itself.
            Image(uiImage: UIImage(named: "AppLogo") ?? UIImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 90, height: 90)
                .cornerRadius(20)
                .opacity(iconOpacity)

            // Layer 1: Ambient halo — wide soft glow behind the icon
            RadialGradient(
                colors: [
                    Color.gloTorchCore.opacity(0.06 * warmth),
                    Color.gloGold.opacity(0.02 * warmth),
                    .clear
                ],
                center: .center,
                startRadius: 30,
                endRadius: 120
            )
            .frame(width: 240, height: 240)

            // Layer 2: Mid halo — warm aura around the icon
            RadialGradient(
                colors: [
                    Color.gloTorchCore.opacity(0.14 * warmth),
                    Color.gloGold.opacity(0.05 * warmth),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 80
            )
            .frame(width: 160, height: 160)

            // Layer 3: Torch ring — clockwise, 10 segments. Filled segments =
            // torch brightness (coarse); the rest are the factor deductions,
            // each colored by the responsible factor. A blurred copy underneath
            // gives the thin line a soft glow.
            glowingRing(filled: torchSegments,
                        filledColor: Color.gloTorchCore,
                        diameter: 112)
                .opacity(isPaused ? 0.35 : 1.0)

            // Layer 4: Screen ring — counterclockwise (mirrored), 10 segments.
            // Filled = screen brightness; same factor attribution for the rest.
            glowingRing(filled: screenSegments,
                        filledColor: .white,
                        diameter: 130)
                .scaleEffect(x: -1, y: 1)
                .opacity(0.85)

            // Ring anchors at 12 o'clock: 🔦 marks the torch ring's start
            // (fills clockwise), ☀ marks the screen ring's start (fills
            // counterclockwise) — without them the bare rings read as abstract
            // decoration.
            Image(systemName: "flashlight.on.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.gloTorchCore.opacity(0.95))
                .shadow(color: Color.gloTorchCore.opacity(0.7), radius: 2)
                .offset(y: -50)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .white.opacity(0.5), radius: 2)
                .offset(y: -69)

            // Operation hints — breathe with the glow
            VStack(spacing: 4) {
                Text(L10n.hintEndWalk)
                Text(L10n.hintAdjust)
            }
            .font(.gloBody(11))
            .foregroundColor(.white.opacity(0.5))
            .offset(y: 100)
        }
        // Breathing + rhythm pulse: gentle breath at 3s cycle, subtle step-sync flutter
        .scaleEffect(0.95 + breathe * 0.05 + cadence * 0.02 * sin(stepPhase))
        .opacity(0.85 + breathe * 0.15 + cadence * 0.04 * sin(stepPhase))
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                breathe = 1
            }
        }
        .onChange(of: cadence) { _ in
            if cadence > 0.1 {
                withAnimation(.easeInOut(duration: 0.5 / max(cadence, 0.3)).repeatForever(autoreverses: false)) {
                    stepPhase += .pi * 2
                }
            }
        }
    }

    /// One coarse 10-segment ring. Filled segments run from the top (12
    /// o'clock); the remaining segments are apportioned to the five factors by
    /// their shortfall shares. Factors don't need to be whole 10% units — each
    /// segment is colored by whichever factor dominates its span.
    private func glowingRing(filled: Int, filledColor: Color, diameter: CGFloat) -> some View {
        ZStack {
            SegmentedRing(filledSegments: filled, shares: factorShares,
                          filledColor: filledColor, diameter: diameter,
                          lineWidth: 1.5)
                .blur(radius: 2.5)
                .opacity(0.5)
            SegmentedRing(filledSegments: filled, shares: factorShares,
                          filledColor: filledColor, diameter: diameter,
                          lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.35), value: filled)
    }

    private struct SegmentedRing: View {
        let filledSegments: Int
        let shares: [Double]
        let filledColor: Color
        let diameter: CGFloat
        let lineWidth: CGFloat

        private let segmentCount = 10
        private let gapDegrees: Double = 3.5

        private static let factorColors: [Color] = [
            .white.opacity(0.55),                                    // ambient
            Color(red: 0.35, green: 0.65, blue: 1.0),                // posture
            Color(red: 0.75, green: 0.45, blue: 1.0),                // dark adaptation
            Color(red: 1.0, green: 0.80, blue: 0.30),                // moon
            Color(red: 0.30, green: 0.90, blue: 0.90)                // weather
        ]

        var body: some View {
            ZStack {
                ForEach(0..<segmentCount, id: \.self) { i in
                    Circle()
                        .trim(from: segmentStart(i), to: segmentEnd(i))
                        .stroke(segmentColor(index: i),
                                style: StrokeStyle(lineWidth: lineWidth,
                                                   lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: diameter, height: diameter)
        }

        private func segmentStart(_ i: Int) -> CGFloat {
            CGFloat(Double(i) / Double(segmentCount) + gapDegrees / 720.0)
        }
        private func segmentEnd(_ i: Int) -> CGFloat {
            CGFloat(Double(i + 1) / Double(segmentCount) - gapDegrees / 720.0)
        }

        private func segmentColor(index: Int) -> Color {
            if index < filledSegments { return filledColor }
            return deductionColor(forSegment: index) ?? Color.white.opacity(0.10)
        }

        /// Dominant factor covering this segment's span within the deduction
        /// space, if any.
        private func deductionColor(forSegment index: Int) -> Color? {
            let total = shares.reduce(0, +)
            guard total > 0.0001, filledSegments < segmentCount else { return nil }
            let dedCount = Double(segmentCount - filledSegments)
            let segStart = Double(index - filledSegments) / dedCount
            let segEnd = Double(index - filledSegments + 1) / dedCount
            var acc = 0.0
            var bestIndex: Int?
            var bestOverlap = 0.0
            for (i, share) in shares.enumerated() {
                let span = share / total
                let overlap = max(0, min(segEnd, acc + span) - max(segStart, acc))
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestIndex = i
                }
                acc += span
            }
            return bestIndex.map { Self.factorColors[$0] }
        }
    }
}
