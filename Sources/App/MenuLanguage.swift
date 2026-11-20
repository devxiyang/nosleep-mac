import Foundation

enum MenuLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: Self { self }
    var locale: Locale { Locale(identifier: rawValue) }

    var nativeName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    static func preference(_ savedValue: String?) -> Self {
        savedValue.flatMap(Self.init(rawValue:)) ?? .english
    }
}
