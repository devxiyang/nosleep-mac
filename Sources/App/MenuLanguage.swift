import Foundation

enum MenuLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case spanish = "es"

    static let supported = allCases.filter { $0 != .system }

    var id: Self { self }
    var locale: Locale { Locale(identifier: rawValue) }

    var nativeName: String {
        switch self {
        case .system: "Follow System"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .german: "Deutsch"
        case .spanish: "Español"
        }
    }

    static func preference(_ savedValue: String?) -> Self {
        savedValue.flatMap(Self.init(rawValue:)) ?? .system
    }

    func resolved(for preferredLanguages: [String] = Bundle.main.preferredLocalizations) -> Self {
        guard self == .system else { return self }

        let matches = Bundle.preferredLocalizations(
            from: Self.supported.map(\.rawValue),
            forPreferences: preferredLanguages + [Self.english.rawValue]
        )
        return matches.first.flatMap(Self.init(rawValue:)) ?? .english
    }
}
