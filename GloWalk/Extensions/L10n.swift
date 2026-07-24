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
    static var cameraAllow: LocalizedStringKey { "camera.allow" }
    static var cameraDeny: LocalizedStringKey { "camera.deny" }

    static var hudDoubleTapToEnd: LocalizedStringKey { "hud.doubleTapToEnd" }
    static var hudOccluded: LocalizedStringKey { "hud.occluded" }
    static var hudGPSUnavailable: LocalizedStringKey { "hud.gpsUnavailable" }
    static var hudGPS: LocalizedStringKey { "hud.gps" }
    static var hudEnding: LocalizedStringKey { "hud.ending" }
    static var hudDrawing: LocalizedStringKey { "hud.drawing" }
    static var hudSteps: LocalizedStringKey { "hud.steps" }

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

    static var settingsTitle: LocalizedStringKey { "settings.title" }
    static var settingsDone: LocalizedStringKey { "settings.done" }
    static var settingsLanguage: LocalizedStringKey { "settings.language" }
    static var settingsData: LocalizedStringKey { "settings.data" }
    static var settingsAbout: LocalizedStringKey { "settings.about" }
    static var settingsFollowSystem: LocalizedStringKey { "settings.followSystem" }
    static var settingsPermissions: LocalizedStringKey { "settings.permissions" }
    static var settingsClearRecords: LocalizedStringKey { "settings.clearRecords" }
    static var settingsCleared: LocalizedStringKey { "settings.cleared" }
    static var settingsRefreshTagline: LocalizedStringKey { "settings.refreshTagline" }
    static var settingsVersion: LocalizedStringKey { "settings.version" }
    static var settingsVersionValue: LocalizedStringKey { "settings.versionValue" }
    static var settingsClearTitle: LocalizedStringKey { "settings.clearTitle" }
    static var settingsClearMessage: LocalizedStringKey { "settings.clearMessage" }
    static var settingsCancel: LocalizedStringKey { "settings.cancel" }
    static var settingsClear: LocalizedStringKey { "settings.clear" }

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

    // MARK: - String helpers for UIKit / data-model contexts
    // LocalizedStringKey only works inside SwiftUI Text views.
    // These return plain String for use in PosterGenerator, LightEngine, etc.

    /// Whether the effective language is Chinese (user pref → system fallback)
    static var isZh: Bool {
        switch UserPreferences.shared.language {
        case "en": return false
        case "zh-Hans": return true
        default: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    /// Localized moon phase name (simplified, for LightEngine HUD card)
    static func moonPhaseName(illumination: Double) -> String {
        switch illumination {
        case 0..<0.05: return isZh ? "新月" : "New Moon"
        case 0.05..<0.35: return isZh ? "蛾眉月" : "Crescent"
        case 0.35..<0.65: return isZh ? "弦月" : "Quarter Moon"
        case 0.65..<0.95: return isZh ? "盈凸月" : "Gibbous"
        default: return isZh ? "满月" : "Full Moon"
        }
    }

    /// Localized moon phase name (detailed, for poster header)
    static func moonPhaseDisplayName(_ phase: String) -> String {
        switch phase {
        case "new_moon": return isZh ? "新月" : "New Moon"
        case "waxing_crescent": return isZh ? "蛾眉月" : "Waxing Crescent"
        case "first_quarter": return isZh ? "上弦月" : "First Quarter"
        case "waxing_gibbous": return isZh ? "盈凸月" : "Waxing Gibbous"
        case "full_moon": return isZh ? "满月" : "Full Moon"
        case "waning_gibbous": return isZh ? "亏凸月" : "Waning Gibbous"
        case "last_quarter": return isZh ? "下弦月" : "Last Quarter"
        case "waning_crescent": return isZh ? "残月" : "Waning Crescent"
        default: return phase
        }
    }

    /// Localized weather condition label
    static func weatherLabel(_ condition: String) -> String {
        switch condition.lowercased() {
        case "rain": return isZh ? "小雨" : "Rain"
        case "drizzle": return isZh ? "毛毛雨" : "Drizzle"
        case "snow": return isZh ? "雪" : "Snow"
        case "fog", "mist": return isZh ? "雾" : "Fog"
        default: return isZh ? "云" : "Cloudy"
        }
    }

    /// Localized poster strings
    static var posterStepsUnit: String { isZh ? " 步" : " steps" }
    static var posterMetersUnit: String { isZh ? " 米" : " m" }
    static var posterKmUnit: String { isZh ? " 公里" : " km" }
    static var posterMinutesUnit: String { isZh ? " 分钟" : " min" }
    static var posterDateFormat: String { isZh ? "M月d日" : "MMM d" }
    static var posterFooter: String {
        isZh ? "踽踽独行，脚下有光 — GloWalk" : "A solitary step, a lantern aglow — GloWalk"
    }
}
