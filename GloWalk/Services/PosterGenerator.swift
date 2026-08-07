import UIKit

final class PosterGenerator {
    @MainActor
    static func generate(session: WalkSession) async -> UIImage {
        let size = UIScreen.main.nativeBounds.size
        let celestialImage = loadCelestialImage(for: session.wrappedStartTime,
                                                moonPhase: session.wrappedMoonPhase)
        // Render the heavy UIGraphics pass on a background executor so the
        // main thread isn't blocked during the end-of-walk transition. The
        // session data is fully loaded (the walk just ended, no concurrent
        // Core Data writes), so reading it off-main is safe here.
        nonisolated(unsafe) let s = session
        return await Task.detached(priority: .userInitiated) {
            render(session: s, size: size, celestialImage: celestialImage)
        }.value
    }

    /// The actual UIGraphicsImageRenderer pass — runs off the main thread.
    nonisolated private static func render(session: WalkSession,
                                           size: CGSize,
                                           celestialImage: UIImage?) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let gold = UIColor(red: 0.769, green: 0.643, blue: 0.290, alpha: 1)

        return renderer.image { ctx in
            // Night sky background
            drawSkyBackground(size: size, ctx: ctx)

            // Centered app icon watermark — brand identity
            drawAppIconWatermark(size: size, ctx: ctx)

            // Celestial image in the top-left corner — the sun by day, the
            // actual moon phase by night, chosen from the walk's own time.
            drawCelestialCorner(celestialImage, size: size, ctx: ctx)

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

    // MARK: - Celestial Image Loading

    /// Which celestial image the poster should show for a walk that started at
    /// `date`: the sun by day, the moon-phase photo by night. The day/night rule
    /// mirrors the HUD's celestial indicator (night = 18:00–05:59).
    static func celestialImageName(for date: Date, moonPhase: String) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        return (hour >= 18 || hour < 6) ? moonPhase : "sun"
    }

    static func loadCelestialImage(for date: Date, moonPhase: String) -> UIImage? {
        let name = celestialImageName(for: date, moonPhase: moonPhase)
        guard let img = UIImage(named: "\(name).jpg") else {
            print("[Poster] Celestial image NOT found: \(name).jpg")
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

    // MARK: - Celestial Corner Decoration

    /// Large celestial body peeking into the top-left corner: the disc is
    /// centred up-left of the canvas so only its lower-right arc is visible.
    /// The visible arc spans ~0.54 of the poster width (the disc itself is
    /// 1.6×), so the sun/moon reads as a prominent backdrop. A gold ring
    /// frames the disc so even the nearly-black new moon stays visible.
    /// The arc's rim falls in the track band's far-left corner — a dark part
    /// of the disc — so the gold track stays readable without recolouring it.
    private static func drawCelestialCorner(_ image: UIImage?, size: CGSize,
                                             ctx: UIGraphicsRendererContext) {
        let radius = size.width * 0.80
        let center = CGPoint(x: -radius * 0.30, y: -radius * 0.22)
        let celestialRect = CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2)

        // Gold ring — frames the disc and keeps a dark new moon visible on the
        // black background.
        let gold = UIColor(red: 0.769, green: 0.643, blue: 0.290, alpha: 1)
        let ring = UIBezierPath(ovalIn: celestialRect)
        gold.withAlphaComponent(0.40).setStroke()
        ring.lineWidth = max(3, size.width * 0.004)
        ring.stroke()

        // Clip to the disc itself so the image's black square corners never
        // show, then draw the lower-right arc over the night-sky background.
        guard let img = image else { return }
        let clipPath = UIBezierPath(ovalIn: celestialRect)
        ctx.cgContext.saveGState()
        clipPath.addClip()
        ctx.cgContext.setAlpha(0.55)
        img.draw(in: celestialRect)
        ctx.cgContext.restoreGState()
    }

    // MARK: - Constellation Path

    private static func drawConstellationPath(session: WalkSession, size: CGSize,
                                               ctx: UIGraphicsRendererContext) {
        let pathMargin = size.width * 0.12
        let pathArea = CGRect(x: pathMargin, y: size.height * 0.22,
                               width: size.width - pathMargin * 2, height: size.height * 0.22)
        guard let projector = PathProjector(points: session.pathPointsArray, area: pathArea),
              session.pathPointsArray.count >= 2 else { return }

        projector.forEachSegment { pt1, pt2, cp1, cp2, avgTorch in
            // Brighter torch (flashlight) → brighter, slightly thicker line.
            // Rendered in native pixels, so the same formula as the HUD
            // multiplied by the device scale gives identical visual weight
            // (the poster is ~3x the HUD's point resolution).
            let alpha = CGFloat(0.3 + avgTorch * 0.5)
            let width = CGFloat((0.6 + avgTorch * 1.0) * UIScreen.main.scale)

            let path = UIBezierPath()
            path.move(to: pt1)
            path.addCurve(to: pt2, controlPoint1: cp1, controlPoint2: cp2)
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
            color: gold, y: 60, size: size, ctx: ctx, shadow: true)
    }

    // MARK: - Stats Card

    private static func drawStats(session: WalkSession, size: CGSize,
                                   gold: UIColor, ctx: UIGraphicsRendererContext) {
        let margin: CGFloat = size.width * 0.10
        let cardY = size.height * 0.48
        let cardH: CGFloat = 360
        let cardRect = CGRect(x: margin, y: cardY, width: size.width - margin * 2, height: cardH)
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
                                          y: CGFloat, size: CGSize, ctx: UIGraphicsRendererContext,
                                          shadow: Bool = false) {
        let margin = size.width * 0.08
        let p = NSMutableParagraphStyle(); p.alignment = .center
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        if shadow {
            let s = NSShadow()
            s.shadowColor = UIColor.black.withAlphaComponent(0.85)
            s.shadowBlurRadius = 6
            s.shadowOffset = CGSize(width: 0, height: 2)
            attrs[.shadow] = s
        }
        (text as NSString).draw(in: CGRect(x: margin, y: y, width: size.width - margin * 2, height: 150),
                                withAttributes: attrs)
    }

}
