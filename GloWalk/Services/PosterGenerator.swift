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

        // Load moon phase image for corner decoration
        let moonImage = loadMoonImage(phase: session.wrappedMoonPhase)

        return renderer.image { ctx in
            // Night sky background
            drawSkyBackground(size: size, ctx: ctx)

            // Centered app icon watermark — brand identity
            drawAppIconWatermark(size: size, ctx: ctx)

            // Moon phase image in top-right corner — tonight's actual moon
            drawMoonCorner(moonImage, size: size, ctx: ctx)

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

    // MARK: - Sky Background

    private static func drawSkyBackground(size: CGSize, ctx: UIGraphicsRendererContext) {
        // Pure black gradient — blends seamlessly with app icon background
        let colors = [
            UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1).cgColor,
            UIColor.black.cgColor
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

    // MARK: - App Icon Watermark (centered, subtle)

    private static func drawAppIconWatermark(size: CGSize, ctx: UIGraphicsRendererContext) {
        guard let icon = UIImage(named: "AppLogo") else { return }

        let iconDim = min(size.width, size.height) * 0.22
        let iconRect = CGRect(
            x: (size.width - iconDim) / 2,
            y: size.height * 0.30 - iconDim / 2,
            width: iconDim,
            height: iconDim
        )

        // Rounded rect clip matching iOS icon proportions
        let cornerRadius = iconDim * 0.225
        let clipPath = UIBezierPath(roundedRect: iconRect, cornerRadius: cornerRadius)
        ctx.cgContext.saveGState()
        clipPath.addClip()
        ctx.cgContext.setAlpha(0.12)
        icon.draw(in: iconRect)
        ctx.cgContext.restoreGState()
    }

    // MARK: - Moon Phase Corner Decoration

    private static func drawMoonCorner(_ image: UIImage?, size: CGSize,
                                        ctx: UIGraphicsRendererContext) {
        guard let img = image else { return }

        let moonDim: CGFloat = 60
        let padding: CGFloat = 16
        let moonRect = CGRect(
            x: padding,
            y: 100,
            width: moonDim,
            height: moonDim
        )

        // Circular clip only — no ring
        let clipPath = UIBezierPath(ovalIn: moonRect)
        ctx.cgContext.saveGState()
        clipPath.addClip()
        ctx.cgContext.setAlpha(0.40)
        img.draw(in: moonRect)
        ctx.cgContext.restoreGState()
    }

    // MARK: - Constellation Path

    private static func drawConstellationPath(session: WalkSession, size: CGSize,
                                               ctx: UIGraphicsRendererContext) {
        let pathArea = CGRect(x: 100, y: size.height * 0.22,
                               width: size.width - 200, height: size.height * 0.22)
        guard let projector = PathProjector(points: session.pathPointsArray, area: pathArea),
              session.pathPointsArray.count >= 2 else { return }

        projector.forEachSegment { pt1, pt2, cp1, cp2, avgLight in
            let alpha = CGFloat(0.3 + (1.0 - avgLight) * 0.5)
            let width = CGFloat(2.0 + (1.0 - avgLight) * 4.0)

            let path = UIBezierPath()
            path.move(to: pt1); path.addLine(to: pt2)
            path.lineWidth = width; path.lineCapStyle = .round
            UIColor(red: 0.769, green: 0.643, blue: 0.290, alpha: alpha).setStroke()
            path.stroke()
        }

        let pts = session.pathPointsArray
        let footprintFont = UIFont.systemFont(ofSize: 28)
        let attrs: [NSAttributedString.Key: Any] = [.font: footprintFont]

        // Start — 👣 emoji
        if let p = projector.startPoint() {
            "👣".draw(at: CGPoint(x: p.x - 16, y: p.y - 16), withAttributes: attrs)
        }

        // End — 🦶 emoji with glow
        if let p = projector.endPoint(), pts.count >= 2 {
            UIColor(red: 0.769, green: 0.643, blue: 0.290, alpha: 0.18).setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36)).fill()
            "🦶".draw(at: CGPoint(x: p.x - 18, y: p.y - 22), withAttributes: attrs)
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
        let cardH: CGFloat = 360
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
            color: gold, y: cardY + 185, size: size, ctx: ctx)
        drawCenteredText(t.localizedExplanation,
            font: wenKaiRegular(18),
            color: UIColor.white.withAlphaComponent(0.4),
            y: cardY + 265, size: size, ctx: ctx)
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
