import UIKit

final class PosterGenerator {
    enum PosterError: Error {
        case noImage, renderingFailed
    }

    static func generate(session: WalkSession) async throws -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
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

        // Large moon offset toward top-left — only right~2/3 and bottom~2/3 visible
        let moonSize: CGFloat = size.height * 0.85
        let offsetX: CGFloat = -moonSize * 0.35  // 1/3 off left edge
        let offsetY: CGFloat = -moonSize * 0.35  // 1/3 off top edge
        let moonRect = CGRect(x: offsetX, y: offsetY,
                              width: moonSize, height: moonSize)

        ctx.cgContext.saveGState()
        ctx.cgContext.setAlpha(0.55)
        img.draw(in: moonRect)
        ctx.cgContext.restoreGState()
    }

    private static func drawMoonOverlay(size: CGSize, ctx: UIGraphicsRendererContext) {
        // No overlay needed — moon blends naturally into night sky
    }

    // MARK: - Header

    private static func drawHeader(session: WalkSession, size: CGSize,
                                    gold: UIColor, ctx: UIGraphicsRendererContext) {
        let formatter = DateFormatter(); formatter.dateFormat = "M月d日"
        let dateStr = formatter.string(from: session.wrappedStartTime)
        let moonCN = moonPhaseDisplayName(session.wrappedMoonPhase)

        drawCenteredText("\(dateStr)  \(moonCN)",
            font: UIFont.systemFont(ofSize: 30, weight: .medium),
            color: gold, y: 60, size: size, ctx: ctx)
    }

    // MARK: - Stats Card

    private static func drawStats(session: WalkSession, size: CGSize,
                                   gold: UIColor, ctx: UIGraphicsRendererContext) {
        let cardY = size.height * 0.5
        let cardH: CGFloat = 360
        let cardRect = CGRect(x: 80, y: cardY, width: size.width - 160, height: cardH)
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 24)
        UIColor.black.withAlphaComponent(0.3).setFill(); cardPath.fill()

        drawCenteredText("\(session.totalSteps) 步",
            font: UIFont.systemFont(ofSize: 80, weight: .light),
            color: gold, y: cardY + 40, size: size, ctx: ctx)

        let dist = session.totalDistance
        let distStr = dist < 1000 ? String(format: "%.0f 米", dist) : String(format: "%.1f 公里", dist/1000)
        var detail = distStr
        if let end = session.endTime {
            detail += "  ·  \(Int(end.timeIntervalSince(session.wrappedStartTime) / 60)) 分钟"
        }
        drawCenteredText(detail, font: UIFont.systemFont(ofSize: 28),
            color: UIColor.white.withAlphaComponent(0.55),
            y: cardY + 140, size: size, ctx: ctx)

        let t = Tagline.random()
        drawCenteredText("\u{201C}\(t.phrase)\u{201D}",
            font: UIFont.systemFont(ofSize: 26, weight: .medium),
            color: gold, y: cardY + 200, size: size, ctx: ctx)
        drawCenteredText(t.explanation,
            font: UIFont.systemFont(ofSize: 17),
            color: UIColor.white.withAlphaComponent(0.35),
            y: cardY + 245, size: size, ctx: ctx)
    }

    // MARK: - Footer

    private static func drawFooter(session: WalkSession, size: CGSize,
                                    gold: UIColor, ctx: UIGraphicsRendererContext) {
        drawCenteredText("踽踽独行，脚下有光 — GloWalk",
            font: UIFont.systemFont(ofSize: 18),
            color: UIColor.white.withAlphaComponent(0.18),
            y: size.height - 140, size: size, ctx: ctx)
    }

    // MARK: - Helpers

    private static func drawCenteredText(_ text: String, font: UIFont, color: UIColor,
                                          y: CGFloat, size: CGSize, ctx: UIGraphicsRendererContext) {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
        (text as NSString).draw(in: CGRect(x: 40, y: y, width: size.width - 80, height: 180),
                                withAttributes: attrs)
    }

    private static func moonPhaseDisplayName(_ phase: String) -> String {
        switch phase {
        case "new_moon": return "新月"; case "waxing_crescent": return "蛾眉月"
        case "first_quarter": return "上弦月"; case "waxing_gibbous": return "盈凸月"
        case "full_moon": return "满月"; case "waning_gibbous": return "亏凸月"
        case "last_quarter": return "下弦月"; case "waning_crescent": return "残月"
        default: return ""
        }
    }
}
