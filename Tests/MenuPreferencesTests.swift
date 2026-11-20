import Testing

@Test func menuLanguageFollowsSystemUntilAnExplicitChoiceIsSaved() {
    #expect(MenuLanguage.preference(nil) == .system)
    #expect(MenuLanguage.preference("invalid") == .system)
    #expect(MenuLanguage.preference("system") == .system)
    #expect(MenuLanguage.preference("zh-Hans") == .simplifiedChinese)
    #expect(MenuLanguage.preference("en") == .english)
    #expect(MenuLanguage.preference("de").resolved(for: ["ja-JP"]) == .german)
}

@Test func systemLanguageMatchesRegionAndFallsBackToTheNextAvailableLanguage() {
    #expect(MenuLanguage.system.resolved(for: ["de-AT"]) == .german)
    #expect(MenuLanguage.system.resolved(for: ["es-MX"]) == .spanish)
    #expect(MenuLanguage.system.resolved(for: ["ko-KR"]) == .korean)
    #expect(MenuLanguage.system.resolved(for: ["zh-TW"]) == .traditionalChinese)
    #expect(MenuLanguage.system.resolved(for: ["zh-CN"]) == .simplifiedChinese)
    #expect(MenuLanguage.system.resolved(for: ["nl-NL", "ja-JP"]) == .japanese)
    #expect(MenuLanguage.system.resolved(for: ["sv-SE"]) == .english)
}

@Test func customIdleDurationAcceptsEitherUnitWithoutLosingPrecision() {
    #expect(IdleDuration.custom(" 10 ", unit: .hours) == IdleDuration(count: 10, unit: .hours))
    #expect(IdleDuration.custom("75", unit: .minutes) == IdleDuration(count: 75, unit: .minutes))
    #expect(IdleDuration.custom("１０", unit: .hours) == IdleDuration(count: 10, unit: .hours))
    #expect(IdleDuration.custom("⑩", unit: .hours) == nil)
    #expect(IdleDuration.custom("0", unit: .minutes) == nil)
    #expect(IdleDuration.custom("1.5", unit: .hours) == nil)
    #expect(IdleDuration.custom("\(Int.max)", unit: .hours) == nil)
}

@Test func idleDurationUsesTheChosenLanguageAndUnit() {
    let duration = IdleDuration(count: 2, unit: .hours)
    let english = duration.formatted(in: MenuLanguage.english.locale)
    let chinese = duration.formatted(in: MenuLanguage.simplifiedChinese.locale)
    #expect(english.contains("hr"))
    #expect(chinese.contains("小时"))
    #expect(IdleDuration(count: 120, unit: .minutes).formatted(in: MenuLanguage.english.locale).contains("120"))
}
