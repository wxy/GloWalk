import UIKit
import CoreData

struct PosterGenerationResult {
    let image: UIImage
    let isNewMemory: Bool
}

/// Value-type snapshot of a walk taken on the main actor, so the poster
/// renderer can run off-main without touching NSManagedObject instances
/// (Core Data objects are not thread-safe, and the health-sync task may still
/// be writing the session while the poster renders).
struct PosterSnapshot {
    let seed: UInt64
    let duration: TimeInterval
    let startTime: Date
    let endTime: Date?
    let moonPhase: String
    let totalSteps: Int64
    let totalDistance: Double
    let pathPoints: [PathProjector.Point]
    let memoryProfile: NightMemoryProfile
    let taglineKey: String
    let memoryPhrase: String
    let brandPhrase: String

    init(session: WalkSession, acquiredMemoryKeys: Set<String> = []) {
        let posterSeed = NightMemoryRandom.seed(for: session.id?.uuidString ?? session.wrappedStartTime.description)
        seed = posterSeed
        duration = session.duration
        startTime = session.wrappedStartTime
        endTime = session.endTime
        moonPhase = session.wrappedMoonPhase
        totalSteps = session.totalSteps
        totalDistance = session.totalDistance
        let recordedPoints = session.pathPointsArray
        pathPoints = recordedPoints.map {
            PathProjector.Point(latitude: $0.latitude,
                                longitude: $0.longitude,
                                torchBrightness: $0.torchBrightness, segmentID: $0.segmentID)
        }
        let profile = NightMemoryProfile(
            duration: session.duration,
            distance: session.totalDistance,
            moonPhase: session.wrappedMoonPhase,
            weatherCondition: session.weatherCondition,
            samples: recordedPoints.map {
                .init(latitude: $0.latitude, longitude: $0.longitude,
                      torchBrightness: $0.torchBrightness, segmentID: $0.segmentID)
            })
        memoryProfile = profile
        let selectedMemory: TaglineItem
        if let savedKey = session.memoryTaglineKey,
           let saved = Tagline.savedNightMemory(key: savedKey) {
            selectedMemory = saved
        } else {
            selectedMemory = Tagline.nightMemory(
                for: profile,
                seed: posterSeed,
                excluding: acquiredMemoryKeys
            )
        }
        taglineKey = selectedMemory.key
        memoryPhrase = selectedMemory.localizedPhrase
        brandPhrase = Tagline.brand(seed: posterSeed, excludingKey: selectedMemory.key).localizedPhrase
    }
}

final class PosterGenerator {
    @MainActor
    static func generate(session: WalkSession) async -> UIImage {
        (await generateWithMetadata(session: session)).image
    }

    @MainActor
    static func generateWithMetadata(session: WalkSession) async -> PosterGenerationResult {
        let acquiredKeys = acquiredMemoryKeys(for: session)
        let hadSavedMemory = session.memoryTaglineKey
            .flatMap { Tagline.savedNightMemory(key: $0) } != nil
        // Snapshot every value the renderer needs on the main actor, then hand
        // only value types to the detached render task.
        let snapshot = PosterSnapshot(session: session, acquiredMemoryKeys: acquiredKeys)
        let isNewMemory = !hadSavedMemory && !acquiredKeys.contains(snapshot.taglineKey)
        if session.memoryTaglineKey != snapshot.taglineKey {
            // A keepsake must not change when a future release adjusts the
            // classification thresholds. Freeze the first selected phrase.
            session.memoryTaglineKey = snapshot.taglineKey
            PersistenceController.shared.save()
        }
        if isNewMemory { NightMemoryDiscovery.markUnseen() }
        let size = UIScreen.main.nativeBounds.size
        let celestialImage = loadCelestialImage(for: snapshot.startTime,
                                                moonPhase: snapshot.moonPhase)
        // Render the heavy UIGraphics pass on a background executor so the
        // main thread isn't blocked during the end-of-walk transition.
        let image = await Task.detached(priority: .userInitiated) {
            render(snapshot: snapshot, size: size, celestialImage: celestialImage)
        }.value
        return PosterGenerationResult(image: image, isNewMemory: isNewMemory)
    }

    @MainActor
    private static func acquiredMemoryKeys(for session: WalkSession) -> Set<String> {
        guard let context = session.managedObjectContext else { return [] }
        let request = NSFetchRequest<WalkSession>(entityName: "WalkSession")
        request.predicate = NSPredicate(format: "memoryTaglineKey != nil")
        do {
            return Set(try context.fetch(request)
                .filter(\.isCompleteRecord)
                .compactMap(\.memoryTaglineKey))
        } catch {
            Log.error("Night memory lookup failed: \(error)")
            return []
        }
    }

    /// The actual UIGraphicsImageRenderer pass — runs off the main thread.
    nonisolated private static func render(snapshot: PosterSnapshot,
                                           size: CGSize,
                                           celestialImage: UIImage?) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let gold = UIColor(red: 0.769, green: 0.643, blue: 0.290, alpha: 1)

        return renderer.image { ctx in
            // Night sky background
            drawSkyBackground(size: size, seed: snapshot.seed, ctx: ctx)

            // Centered app icon watermark — brand identity
            drawAppIconWatermark(size: size, ctx: ctx)

            // Celestial image in the top-left corner — the sun by day, the
            // actual moon phase by night, chosen from the walk's own time.
            drawCelestialCorner(celestialImage, size: size, ctx: ctx)

            // Constellation path overlay
            drawConstellationPath(snapshot: snapshot, size: size, ctx: ctx)

            // The walk-specific sentence is the poster's narrative center.
            drawMemoryPhrase(snapshot: snapshot, size: size, gold: gold, ctx: ctx)

            // Stats card carries facts only.
            drawStats(snapshot: snapshot, size: size, gold: gold, ctx: ctx)

            // Product voice sits below the facts as a quiet signature.
            drawBrandPhrase(snapshot: snapshot, size: size, ctx: ctx)

            // Date + moon name at top
            drawHeader(snapshot: snapshot, size: size, gold: gold, ctx: ctx)

            // Brand mark at bottom
            drawFooter(size: size, ctx: ctx)
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
            Log.error("[Poster] Celestial image NOT found: \(name).jpg")
            return nil
        }
        return img
    }

    // MARK: - Sky Background

    private static func drawSkyBackground(size: CGSize, seed: UInt64, ctx: UIGraphicsRendererContext) {
        // Pure black gradient — blends seamlessly with app icon background
        let colors = [
            UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1).cgColor,
            UIColor.black.cgColor
        ] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: colors, locations: [0, 1])!
        ctx.cgContext.drawLinearGradient(g, start: .zero,
            end: CGPoint(x: 0, y: size.height), options: [])

        var random = NightMemoryRandom(seed: seed)
        // Stars
        for _ in 0..<80 {
            let x = CGFloat.random(in: 0...size.width, using: &random)
            let y = CGFloat.random(in: 0...size.height * 0.5, using: &random)
            let r = CGFloat.random(in: 0.5...2.5, using: &random)
            UIColor.white.withAlphaComponent(CGFloat.random(in: 0.15...0.6, using: &random)).setFill()
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

    /// Large celestial body peeking into the top-left corner. The disc shares
    /// CelestialGeometry with the HUD (1.0× width, centered just off the
    /// corner) so roughly half of it is visible — enough to tell the moon's
    /// phase (full vs half vs crescent) — while staying a backdrop, not a
    /// full centered disc.
    private static func drawCelestialCorner(_ image: UIImage?, size: CGSize,
                                             ctx: UIGraphicsRendererContext) {
        let radius = size.width * CelestialGeometry.radiusFactor
        let center = CGPoint(
            x: radius * CelestialGeometry.centerXFactor,
            y: radius * CelestialGeometry.centerYFactor)
        let celestialRect = CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2)

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

    private static func drawConstellationPath(snapshot: PosterSnapshot, size: CGSize,
                                               ctx: UIGraphicsRendererContext) {
        let pathMargin = size.width * 0.12
        let pathArea = CGRect(x: pathMargin, y: size.height * 0.22,
                               width: size.width - pathMargin * 2, height: size.height * 0.22)
        guard let projector = PathProjector(points: snapshot.pathPoints, area: pathArea),
              snapshot.pathPoints.count >= 2 else { return }

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

        let pts = snapshot.pathPoints
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

    private static func drawHeader(snapshot: PosterSnapshot, size: CGSize,
                                    gold: UIColor, ctx: UIGraphicsRendererContext) {
        let df = DateFormatter()
        df.dateFormat = L10n.posterDateFormat
        df.locale = L10n.isZh ? Locale(identifier: "zh-Hans") : Locale(identifier: "en")
        let dateStr = df.string(from: snapshot.startTime)
        let moonName = L10n.moonPhaseDisplayName(snapshot.moonPhase)

        drawCenteredText("\(dateStr)  \(moonName)",
            font: wenKaiMedium(28),
            color: gold, y: 60, size: size, ctx: ctx, shadow: true)
    }

    // MARK: - Copy Hierarchy

    private static func drawMemoryPhrase(snapshot: PosterSnapshot, size: CGSize,
                                         gold: UIColor, ctx: UIGraphicsRendererContext) {
        drawCenteredText("\u{201C}\(snapshot.memoryPhrase)\u{201D}",
            font: wenKaiMedium(30),
            color: gold, y: size.height * 0.475, size: size, ctx: ctx,
            textHeight: size.height * 0.10)
    }

    // MARK: - Stats Card

    private static func drawStats(snapshot: PosterSnapshot, size: CGSize,
                                   gold: UIColor, ctx: UIGraphicsRendererContext) {
        let margin: CGFloat = size.width * 0.10
        let cardY = size.height * 0.60
        let cardH = max(250, min(340, size.height * 0.16))
        let cardRect = CGRect(x: margin, y: cardY, width: size.width - margin * 2, height: cardH)
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 24)
        UIColor.black.withAlphaComponent(0.3).setFill(); cardPath.fill()

        drawCenteredText("\(snapshot.totalSteps)\(L10n.posterStepsUnit)",
            font: wenKaiLight(72),
            color: gold, y: cardY + cardH * 0.10, size: size, ctx: ctx)

        let dist = snapshot.totalDistance
        let distStr = dist < 1000
            ? String(format: "%.0f%@", dist, L10n.posterMetersUnit)
            : String(format: "%.1f%@", dist / 1000, L10n.posterKmUnit)
        var detail = distStr
        if snapshot.endTime != nil {
            detail += "  ·  \(Int(snapshot.duration / 60))\(L10n.posterMinutesUnit)"
        }
        drawCenteredText(detail, font: wenKaiRegular(26),
            color: UIColor.white.withAlphaComponent(0.55),
            y: cardY + cardH * 0.58, size: size, ctx: ctx)
    }

    private static func drawBrandPhrase(snapshot: PosterSnapshot, size: CGSize,
                                        ctx: UIGraphicsRendererContext) {
        let cardH = max(250, min(340, size.height * 0.16))
        let y = size.height * 0.60 + cardH + size.height * 0.035
        drawCenteredText(snapshot.brandPhrase,
            font: wenKaiRegular(20),
            color: UIColor.white.withAlphaComponent(0.52),
            y: y, size: size, ctx: ctx, textHeight: 70)
    }

    // MARK: - Footer

    private static func drawFooter(size: CGSize, ctx: UIGraphicsRendererContext) {
        drawCenteredText("G L O W A L K",
            font: UIFont.systemFont(ofSize: 14, weight: .medium),
            color: UIColor.white.withAlphaComponent(0.22),
            y: size.height - 30, size: size, ctx: ctx)
    }

    // MARK: - Handwriting Font Helpers (language-aware)

    private static func wenKaiLight(_ size: CGFloat) -> UIFont {
        GloUIFont.display(size)
    }
    private static func wenKaiRegular(_ size: CGFloat) -> UIFont {
        GloUIFont.body(size)
    }
    private static func wenKaiMedium(_ size: CGFloat) -> UIFont {
        GloUIFont.headline(size)
    }

    // MARK: - Helpers

    private static func drawCenteredText(_ text: String, font: UIFont, color: UIColor,
                                          y: CGFloat, size: CGSize, ctx: UIGraphicsRendererContext,
                                          shadow: Bool = false, textHeight: CGFloat = 150) {
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
        (text as NSString).draw(in: CGRect(x: margin, y: y,
                                          width: size.width - margin * 2, height: textHeight),
                                withAttributes: attrs)
    }

}
