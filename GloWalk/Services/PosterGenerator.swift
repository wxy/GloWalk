import UIKit

final class PosterGenerator {
    enum PosterError: Error {
        case noImage, renderingFailed
    }

    @MainActor
    static func generate(session: WalkSession) async throws -> UIImage {
        let size = UIScreen.main.nativeBounds.size
        let renderer = UIGraphicsImageRenderer(size: size)
        let gold = UIColor(red: 0.769, green: 0.643, blue: 0.290, alpha: 1)

        // Load moon phase image
        let moonImage = loadMoonImage(phase: session.wrappedMoonPhase)

        return renderer.image { ctx in
            // Night sky background
            drawSkyBackground(size: size, ctx: ctx)

            // NASA moon image centered
            drawMoonImage(moonImage, size: size, ctx: ctx)

            // Semi-transparent tint overlay
            drawMoonOverlay(size: size, ctx: ctx)

            // Constellation path overlay
            drawConstellationPath(session: session, size: size, ctx: ctx)

            // Stats card
            drawStats(session: session, size: size, gold: gold, ctx: ctx)

            // Date + moon name at top
            drawHeader(session: session, size: size, gold: gold, ctx: ctx)

            // Tagline + brand at bottom
            drawFooter(session: session, size: size, gold: gold, ctx: ctx)
        }
    }

    // MARK: - Moon Image Loading

    static func loadMoonImage(phase: String) -> UIImage? {
        guard let img = UIImage(named: "\(phase).jpg") else {
            print("[Poster] Moon image NOT found: \(phase).jpg")
            return nil
        }
        return img
    }

    /// Convenience: load the moon image for the current moon phase
    static func currentMoonImage() -> UIImage? {
        loadMoonImage(phase: MoonPhase.current().phase)
    }

    // MARK: - Sky Background

    private static func drawSkyBackground(size: CGSize, ctx: UIGraphicsRendererContext) {
        let colors = [
            UIColor(red: 0.04, green: 0.04, blue: 0.12, alpha: 1).cgColor,
            UIColor(red: 0.01, green: 0.01, blue: 0.04, alpha: 1).cgColor
        ] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: colors, locations: [0, 1])!
        ctx.cgContext.drawLinearGradient(g, start: .zero,
            end: CGPoint(x: 0, y: size.height), options: [])

        // Stars
        for _ in 0..<80 {
            let x = CGFloat.random(in: 0...size.width)
            let y = CGFloat.random(in: 0...size.height * 0.5)
            let r = CGFloat.random(in: 0.5...2.5)
            UIColor.white.withAlphaComponent(CGFloat.random(in: 0.15...0.6)).setFill()
            UIBezierPath(ovalIn: CGRect(x: x, y: y, width: r, height: r)).fill()
        }
    }

    // MARK: - Moon Image + Overlay

    private static func drawMoonImage(_ image: UIImage?, size: CGSize,
                                       ctx: UIGraphicsRendererContext) {
        guard let img = image else { return }

        // Remove near-black background from NASA image, keeping moon surface details
        let processedImg = removeBlackBackground(img)

        let moonSize: CGFloat = size.height * 0.85
        let offsetX: CGFloat = -moonSize * 0.35
        let offsetY: CGFloat = -moonSize * 0.35
        let moonRect = CGRect(x: offsetX, y: offsetY,
                              width: moonSize, height: moonSize)

        ctx.cgContext.saveGState()
        ctx.cgContext.setAlpha(0.55)
        processedImg.draw(in: moonRect)
        ctx.cgContext.restoreGState()
    }

    /// Makes near-black pixels transparent (space background) while
    /// preserving the moon's dark surface features (maria).
    private static func removeBlackBackground(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width, height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let ctx = CGContext(data: &pixels, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Threshold: RGB all < 25 → space black → make transparent
        // Moon's dark areas are usually > 30-40 in at least one channel
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[i]), g = Int(pixels[i+1]), b = Int(pixels[i+2])
            if r < 25 && g < 25 && b < 25 {
                pixels[i+3] = 0  // alpha = 0 (transparent)
            }
        }

        guard let newCG = ctx.makeImage() else { return image }
        return UIImage(cgImage: newCG)
    }

    private static func drawMoonOverlay(size: CGSize, ctx: UIGraphicsRendererContext) {
        // No overlay needed — moon blends naturally into night sky
    }

    // MARK: - Constellation Path

    private static func drawConstellationPath(session: WalkSession, size: CGSize,
                                               ctx: UIGraphicsRendererContext) {
        let pathArea = CGRect(x: 100, y: size.height * 0.22,
                               width: size.width - 200, height: size.height * 0.22)
        guard let projector = PathProjector(points: session.pathPointsArray, area: pathArea),
              session.pathPointsArray.count >= 2 else { return }

        projector.forEachSegment { pt1, pt2, _, _, avgLight in
            let alpha = CGFloat(0.3 + (1.0 - avgLight) * 0.5)
            let width = CGFloat(2.0 + (1.0 - avgLight) * 4.0)

            let path = UIBezierPath()
            path.move(to: pt1); path.addLine(to: pt2)
            path.lineWidth = width; path.lineCapStyle = .round
            UIColor(red: 0.769, green: 0.643, blue: 0.290, alpha: alpha).setStroke()
            path.stroke()
        }

        // Start marker
        if let p = projector.startPoint() {
            UIBezierPath(ovalIn: CGRect(x: p.x-6, y: p.y-6, width: 12, height: 12)).fill()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x-6, y: p.y-6, width: 12, height: 12)).fill()
        }
    }

    // MARK: - Header

    private static func drawHeader(session: WalkSession, size: CGSize,
                                    gold: UIColor, ctx: UIGraphicsRendererContext) {
        let df = DateFormatter()
        df.dateFormat = L10n.posterDateFormat
        df.locale = L10n.isZh ? Locale(identifier: "zh-Hans") : Locale(identifier: "en")
        let dateStr = df.string(from: session.wrappedStartTime)
        let moonName = L10n.moonPhaseDisplayName(session.wrappedMoonPhase)

        drawCenteredText("\(dateStr)  \(moonName)",
            font: wenKaiMedium(28),
            color: gold, y: 60, size: size, ctx: ctx)
    }

    // MARK: - Stats Card

    private static func drawStats(session: WalkSession, size: CGSize,
                                   gold: UIColor, ctx: UIGraphicsRendererContext) {
        let cardY = size.height * 0.48
        let cardH: CGFloat = 300
        let cardRect = CGRect(x: 80, y: cardY, width: size.width - 160, height: cardH)
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 24)
        UIColor.black.withAlphaComponent(0.3).setFill(); cardPath.fill()

        drawCenteredText("\(session.totalSteps)\(L10n.posterStepsUnit)",
            font: wenKaiLight(72),
            color: gold, y: cardY + 30, size: size, ctx: ctx)

        let dist = session.totalDistance
        let distStr = dist < 1000
            ? String(format: "%.0f%@", dist, L10n.posterMetersUnit)
            : String(format: "%.1f%@", dist / 1000, L10n.posterKmUnit)
        var detail = distStr
        if let end = session.endTime {
            detail += "  ·  \(Int(end.timeIntervalSince(session.wrappedStartTime) / 60))\(L10n.posterMinutesUnit)"
        }
        drawCenteredText(detail, font: wenKaiRegular(26),
            color: UIColor.white.withAlphaComponent(0.55),
            y: cardY + 120, size: size, ctx: ctx)

        let t = Tagline.random()
        drawCenteredText("\u{201C}\(t.localizedPhrase)\u{201D}",
            font: wenKaiMedium(24),
            color: gold, y: cardY + 170, size: size, ctx: ctx)
        drawCenteredText(t.localizedExplanation,
            font: wenKaiRegular(18),
            color: UIColor.white.withAlphaComponent(0.4),
            y: cardY + 210, size: size, ctx: ctx)
    }

    // MARK: - Footer

    private static func drawFooter(session: WalkSession, size: CGSize,
                                    gold: UIColor, ctx: UIGraphicsRendererContext) {
        drawCenteredText(L10n.posterFooter,
            font: wenKaiRegular(16),
            color: UIColor.white.withAlphaComponent(0.2),
            y: size.height - 30, size: size, ctx: ctx)
    }

    // MARK: - WenKai Font Helpers

    private static func wenKaiLight(_ size: CGFloat) -> UIFont {
        UIFont(name: "LXGW WenKai Light", size: size) ?? UIFont.systemFont(ofSize: size, weight: .light)
    }
    private static func wenKaiRegular(_ size: CGFloat) -> UIFont {
        UIFont(name: "LXGW WenKai", size: size) ?? UIFont.systemFont(ofSize: size)
    }
    private static func wenKaiMedium(_ size: CGFloat) -> UIFont {
        UIFont(name: "LXGW WenKai Medium", size: size) ?? UIFont.systemFont(ofSize: size, weight: .medium)
    }

    // MARK: - Helpers

    private static func drawCenteredText(_ text: String, font: UIFont, color: UIColor,
                                          y: CGFloat, size: CGSize, ctx: UIGraphicsRendererContext) {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        (text as NSString).draw(in: CGRect(x: 40, y: y, width: size.width - 80, height: 150),
                                withAttributes: attrs)
    }

}
