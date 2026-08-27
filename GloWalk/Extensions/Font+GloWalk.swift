import SwiftUI
import UIKit

/// Bundled font families, keyed by the language they serve:
///   * LXGW WenKai — Chinese (simplified/traditional), English and the
///     Tier-2 European languages (fr/de/es/pt-BR/it/ru, incl. Cyrillic)
///   * Klee One — Japanese (the font LXGW WenKai derives from; correct JP
///     kanji forms, kana and punctuation)
///   * LXGW WenKai KR — Korean (the official Korean edition of WenKai)
private enum GloFontFamily {
    static let wnkLight = "LXGW WenKai Light"
    static let wnkRegular = "LXGW WenKai"
    static let wnkMedium = "LXGW WenKai Medium"
    static let wnkMonoLight = "LXGW WenKai Mono Light"

    static let kleeRegular = "Klee One"
    static let kleeSemiBold = "Klee One SemiBold"

    static let krLight = "LXGW WenKai KR Light"
    static let krRegular = "LXGW WenKai KR"
    static let krMedium = "LXGW WenKai KR Medium"
    static let krMonoLight = "LXGW WenKai Mono KR Light"
}

/// The font family set for the effective UI language. Japanese HUD numbers
/// keep the WenKai Mono face (its subset includes the 歩/分 units), so the
/// mono slot maps Japanese to the same face as the default set.
private enum GloFontSet {
    case wenkai, klee, wenkaiKR

    static var active: GloFontSet {
        switch L10n.languageCode {
        case "ja": return .klee
        case "ko": return .wenkaiKR
        default: return .wenkai
        }
    }
}

extension Font {
    // Semantic helpers
    static func gloDisplay(_ size: CGFloat) -> Font {
        switch GloFontSet.active {
        case .wenkai: return .custom(GloFontFamily.wnkLight, size: size)
        case .klee: return .custom(GloFontFamily.kleeRegular, size: size)
        case .wenkaiKR: return .custom(GloFontFamily.krLight, size: size)
        }
    }
    static func gloBody(_ size: CGFloat = 14) -> Font {
        switch GloFontSet.active {
        case .wenkai: return .custom(GloFontFamily.wnkRegular, size: size)
        case .klee: return .custom(GloFontFamily.kleeRegular, size: size)
        case .wenkaiKR: return .custom(GloFontFamily.krRegular, size: size)
        }
    }
    static func gloHeadline(_ size: CGFloat = 17) -> Font {
        switch GloFontSet.active {
        case .wenkai: return .custom(GloFontFamily.wnkMedium, size: size)
        case .klee: return .custom(GloFontFamily.kleeSemiBold, size: size)
        case .wenkaiKR: return .custom(GloFontFamily.krMedium, size: size)
        }
    }
    static func gloMono(_ size: CGFloat = 12) -> Font {
        switch GloFontSet.active {
        case .wenkai: return .custom(GloFontFamily.wnkMonoLight, size: size)
        case .klee: return .custom(GloFontFamily.wnkMonoLight, size: size)
        case .wenkaiKR: return .custom(GloFontFamily.krMonoLight, size: size)
        }
    }
}

/// UIFont resolution for UIKit rendering contexts (navigation bar, poster),
/// mirroring the Font helpers above.
enum GloUIFont {
    static func display(_ size: CGFloat) -> UIFont {
        let name: String
        switch GloFontSet.active {
        case .wenkai: name = GloFontFamily.wnkLight
        case .klee: name = GloFontFamily.kleeRegular
        case .wenkaiKR: name = GloFontFamily.krLight
        }
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: .light)
    }

    static func body(_ size: CGFloat) -> UIFont {
        let name: String
        switch GloFontSet.active {
        case .wenkai: name = GloFontFamily.wnkRegular
        case .klee: name = GloFontFamily.kleeRegular
        case .wenkaiKR: name = GloFontFamily.krRegular
        }
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
    }

    static func headline(_ size: CGFloat) -> UIFont {
        let name: String
        switch GloFontSet.active {
        case .wenkai: name = GloFontFamily.wnkMedium
        case .klee: name = GloFontFamily.kleeSemiBold
        case .wenkaiKR: name = GloFontFamily.krMedium
        }
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: .medium)
    }
}
