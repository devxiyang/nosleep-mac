import Foundation

struct IdleDuration: Hashable {
    let count: Int
    let unit: DurationUnit

    static let presets = [5, 10, 15, 30].map { Self(count: $0, unit: .minutes) }
        + [1, 2, 10].map { Self(count: $0, unit: .hours) }

    static func custom(_ text: String, unit: DurationUnit) -> Self? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = input.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
            ? input.compactMap(\.wholeNumberValue).map(String.init).joined()
            : input
        guard let count = Int(normalized), unit.totalMinutes(count) != nil else { return nil }
        return Self(count: count, unit: unit)
    }

    func formatted(in locale: Locale) -> String {
        let seconds = Int64(unit.totalMinutes(count) ?? 0) * 60
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = unit == .hours ? [.hours] : [.minutes]
        return Duration.seconds(seconds).formatted(.units(allowed: allowed, width: .abbreviated).locale(locale))
    }
}
