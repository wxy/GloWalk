import SwiftUI

/// Centralized localization. Add new languages by extending Localizable.xcstrings.
/// Usage: Text(L10n.privacyTitle) or L10n.privacyTitle as String
enum L10n {
    static var privacyTitle: LocalizedStringKey { "privacy.title" }
    static var privacyItem1: LocalizedStringKey { "privacy.item1" }
    static var privacyItem2: LocalizedStringKey { "privacy.item2" }
    static var privacyItem3: LocalizedStringKey { "privacy.item3" }
    static var privacyItem4: LocalizedStringKey { "privacy.item4" }
    static var privacyStart: LocalizedStringKey { "privacy.start" }

    static var cameraTitle: LocalizedStringKey { "camera.title" }
    static var cameraDescription: LocalizedStringKey { "camera.description" }
    static var cameraContinue: LocalizedStringKey { "camera.continue" }

    static var locationTitle: LocalizedStringKey { "location.title" }
    static var locationDescription: LocalizedStringKey { "location.description" }
    static var locationContinue: LocalizedStringKey { "location.continue" }

    static var hudOccluded: LocalizedStringKey { "hud.occluded" }
    static var hudDaylight: LocalizedStringKey { "hud.daylight" }
    static var hudCameraDenied: LocalizedStringKey { "hud.cameraDenied" }
    static var hudCameraDeniedTitle: LocalizedStringKey { "hud.cameraDeniedTitle" }
    static var hudCameraDeniedMessage: LocalizedStringKey { "hud.cameraDeniedMessage" }
    static var hudCameraDeniedSettings: LocalizedStringKey { "hud.cameraDeniedSettings" }
    static var hudCameraDeniedDismiss: LocalizedStringKey { "hud.cameraDeniedDismiss" }
    static var hudDrawing: LocalizedStringKey { "hud.drawing" }
    static var hudZeroStep: LocalizedStringKey { "hud.zeroStep" }
    static var hintEndWalk: LocalizedStringKey { "hud.hint.endWalk" }
    static var hintAdjust: LocalizedStringKey { "hud.hint.adjust" }

    static var posterShare: LocalizedStringKey { "poster.share" }
    static var posterSave: LocalizedStringKey { "poster.save" }
    static var posterSaved: LocalizedStringKey { "poster.saved" }
    static var posterDone: LocalizedStringKey { "poster.done" }
    static var posterGenerateFailed: LocalizedStringKey { "poster.generateFailed" }
    static var posterClose: LocalizedStringKey { "poster.close" }

    static var historyTitle: LocalizedStringKey { "history.title" }
    static var historyEmpty: LocalizedStringKey { "history.empty" }
    static var historyEmptyHint1: LocalizedStringKey { "history.emptyHint1" }
    static var historyEmptyHint2: LocalizedStringKey { "history.emptyHint2" }
    static var historyEmptyHint3: LocalizedStringKey { "history.emptyHint3" }
    static var historyNewWalk: LocalizedStringKey { "history.newWalk" }
    static var historyStartWalk: LocalizedStringKey { "history.startWalk" }
    static var historyResumeWalk: LocalizedStringKey { "history.resumeWalk" }

    static var settingsTitle: LocalizedStringKey { "settings.title" }
    static var settingsDone: LocalizedStringKey { "settings.done" }
    static var settingsLanguage: LocalizedStringKey { "settings.language" }
    static var settingsLanguageSimplified: LocalizedStringKey { "settings.language.simplified" }
    static var settingsLanguageTraditional: LocalizedStringKey { "settings.language.traditional" }
    static var settingsData: LocalizedStringKey { "settings.data" }
    static var settingsAbout: LocalizedStringKey { "settings.about" }
    static var settingsFollowSystem: LocalizedStringKey { "settings.followSystem" }
    static var settingsPermissions: LocalizedStringKey { "settings.permissions" }
    static var settingsClearRecords: LocalizedStringKey { "settings.clearRecords" }
    static var settingsCleared: LocalizedStringKey { "settings.cleared" }
    static var settingsRefreshTagline: LocalizedStringKey { "settings.refreshTagline" }
    static var settingsHealth: LocalizedStringKey { "settings.health" }
    static var permissionsHealthFeature1: LocalizedStringKey { "permissions.health.feature1" }
    static var permissionsHealthFeature2: LocalizedStringKey { "permissions.health.feature2" }
    static var permissionsHealthUnavailable: LocalizedStringKey { "permissions.health.unavailable" }
    static var summaryHealthSyncing: LocalizedStringKey { "summary.health.syncing" }
    static var summaryHealthSynced: LocalizedStringKey { "summary.health.synced" }
    static var summaryHealthFailed: LocalizedStringKey { "summary.health.failed" }
    static var settingsVersion: LocalizedStringKey { "settings.version" }
    static var settingsHelp: LocalizedStringKey { "settings.help" }
    static var settingsHelpSection: LocalizedStringKey { "settings.helpSection" }
    static var settingsClearTitle: LocalizedStringKey { "settings.clearTitle" }
    static var settingsClearMessage: LocalizedStringKey { "settings.clearMessage" }
    static var settingsCancel: LocalizedStringKey { "settings.cancel" }
    static var settingsClear: LocalizedStringKey { "settings.clear" }

    static var aboutWeatherLegal: LocalizedStringKey { "about.weatherLegal" }
    static var aboutWebsite: LocalizedStringKey { "about.website" }
    static var aboutFontLicense: LocalizedStringKey { "about.fontLicense" }
    static var aboutGitHub: LocalizedStringKey { "about.gitHub" }

    static var permissionsCamera: LocalizedStringKey { "permissions.camera" }
    static var permissionsLocation: LocalizedStringKey { "permissions.location" }
    static var permissionsAuthorized: LocalizedStringKey { "permissions.authorized" }
    static var permissionsDenied: LocalizedStringKey { "permissions.denied" }
    static var permissionsNotDetermined: LocalizedStringKey { "permissions.notDetermined" }
    static var permissionsRestricted: LocalizedStringKey { "permissions.restricted" }
    static var permissionsCameraFeature1: LocalizedStringKey { "permissions.cameraFeature1" }
    static var permissionsCameraFeature2: LocalizedStringKey { "permissions.cameraFeature2" }
    static var permissionsLocationFeature1: LocalizedStringKey { "permissions.locationFeature1" }
    static var permissionsLocationFeature2: LocalizedStringKey { "permissions.locationFeature2" }
    static var permissionsLocationFeature3: LocalizedStringKey { "permissions.locationFeature3" }
    static var permissionsOpenSettings: LocalizedStringKey { "permissions.openSettings" }

    // Help items — 7 sections
    static var helpAutoTitle: LocalizedStringKey { "help.autoTitle" }
    static var helpAutoDesc: LocalizedStringKey { "help.autoDesc" }
    static var helpDragTitle: LocalizedStringKey { "help.dragTitle" }
    static var helpDragDesc: LocalizedStringKey { "help.dragDesc" }
    static var helpLongPressTitle: LocalizedStringKey { "help.longPressTitle" }
    static var helpLongPressDesc: LocalizedStringKey { "help.longPressDesc" }
    static var helpTogglesTitle: LocalizedStringKey { "help.togglesTitle" }
    static var helpTogglesDesc: LocalizedStringKey { "help.togglesDesc" }
    static var helpEndTitle: LocalizedStringKey { "help.endTitle" }
    static var helpEndDesc: LocalizedStringKey { "help.endDesc" }
    static var helpDismissTitle: LocalizedStringKey { "help.dismissTitle" }
    static var helpDismissDesc: LocalizedStringKey { "help.dismissDesc" }
    static var helpHistoryTitle: LocalizedStringKey { "help.historyTitle" }
    static var helpHistoryDesc: LocalizedStringKey { "help.historyDesc" }
    static var helpNavTitle: LocalizedStringKey { "help.navTitle" }

    // MARK: - String helpers for UIKit / data-model contexts
    // LocalizedStringKey only works inside SwiftUI Text views.
    // These return plain String from the string catalog (NSLocalizedString), so
    // they follow Bundle's effective language (incl. the in-app override) and
    // support every language added to Localizable.xcstrings.

    /// Resolved language code ("en" / "zh-Hans" / "zh-Hant") from the user preference.
    static var languageCode: String {
        switch UserPreferences.shared.language {
        case "en": return "en"
        case "zh-Hans": return "zh-Hans"
        case "zh-Hant": return "zh-Hant"
        default:
            let lang = Locale.preferredLanguages.first ?? "en"
            if lang.hasPrefix("zh") {
                return lang.contains("Hant") ? "zh-Hant" : "zh-Hans"
            }
            return "en"
        }
    }

    /// Whether the effective language is a Chinese variant (simplified or traditional).
    static var isZh: Bool {
        languageCode.hasPrefix("zh")
    }

    /// Catalog lookup that resolves against the user's explicit language's .lproj
    /// bundle. Bundle.main's preferredLocalizations can be stale after in-app
    /// switching, which would otherwise fall back to English/simplified.
    private static func str(_ key: String) -> String {
        let code = languageCode
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let b = Bundle(path: path) {
            return b.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static var factorAmbient: String { str("factor.ambient") }
    static var factorPosture: String { str("factor.posture") }
    static var factorDark: String { str("factor.dark") }

    /// Localized ambient-brightness descriptor for the ambient factor card.
    /// "明亮/Bright" is gated on the debounced daylight state (the same state
    /// that turns the torch off), so the label never claims bright while the
    /// torch is still on. Below that, the raw front-camera reading (which
    /// auto-exposure compresses to roughly 0–0.5) is bucketed: ≥0.5 fairly
    /// bright (bright but not yet daylight-confirmed), 0.2–0.5 dim, <0.2 dark.
    static func ambientBrightnessLabel(_ level: Double, isDaylight: Bool) -> String {
        // "明亮" is not reserved for confirmed daylight: a genuinely bright
        // indoor scene (exposure-based ambient ≥ 0.7) should read as bright too.
        if isDaylight || level >= 0.7 { return str("ambient.level.bright") }
        switch level {
        case 0.5..<0.7: return str("ambient.level.fairlyBright")  // bright, not yet confirmed
        case 0.2..<0.5: return str("ambient.level.dim")        // typical indoor
        default: return str("ambient.level.dark")              // night / very dark
        }
    }

    /// Localized moon phase name (simplified, for LightEngine HUD card)
    static func moonPhaseName(illumination: Double) -> String {
        switch illumination {
        case 0..<0.05: return str("moon.hud.newMoon")
        case 0.05..<0.35: return str("moon.hud.crescent")
        case 0.35..<0.65: return str("moon.hud.quarter")
        case 0.65..<0.95: return str("moon.hud.gibbous")
        default: return str("moon.hud.fullMoon")
        }
    }

    /// Localized moon phase name (detailed, for poster header)
    static func moonPhaseDisplayName(_ phase: String) -> String {
        switch phase {
        case "new_moon": return str("moon.name.newMoon")
        case "waxing_crescent": return str("moon.name.waxingCrescent")
        case "first_quarter": return str("moon.name.firstQuarter")
        case "waxing_gibbous": return str("moon.name.waxingGibbous")
        case "full_moon": return str("moon.name.fullMoon")
        case "waning_gibbous": return str("moon.name.waningGibbous")
        case "last_quarter": return str("moon.name.lastQuarter")
        case "waning_crescent": return str("moon.name.waningCrescent")
        default: return phase
        }
    }

    /// Localized weather condition label
    static func weatherLabel(_ condition: String) -> String {
        switch condition.lowercased() {
        case "rain": return str("weather.rain")
        case "drizzle": return str("weather.drizzle")
        case "snow": return str("weather.snow")
        case "fog", "mist": return str("weather.fog")
        default: return str("weather.cloudy")
        }
    }

    /// Localized poster strings
    static var posterStepsUnit: String { str("poster.unit.steps") }
    static var posterMetersUnit: String { str("poster.unit.meters") }
    static var posterKmUnit: String { str("poster.unit.km") }
    static var posterMinutesUnit: String { str("poster.unit.minutes") }
    static var posterDateFormat: String { str("poster.dateFormat") }
    static var posterFooter: String { str("poster.footer") }

    /// Localized HUD units / formats
    static var hudUnitSteps: String { str("hud.unit.steps") }
    static var hudUnitMinutes: String { str("hud.unit.minutes") }
    static var hudDistanceMeters: String { str("hud.distance.meters") }
    static var hudDistanceKm: String { str("hud.distance.km") }

    /// Localized history-row units
    static var historyUnitSteps: String { str("history.unit.steps") }
    static var historyUnitMeters: String { str("history.unit.meters") }
    static var historyUnitMinutes: String { str("history.unit.minutes") }

    /// Localized app display name for the version line
    static var versionName: String { str("settings.version.name") }
}
