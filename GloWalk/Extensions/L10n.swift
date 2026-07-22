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
}
