import Testing

@Test func menuLanguageUsesEnglishUntilARecognizedOptionIsSelected() {
    #expect(MenuLanguage.preference(nil) == .english)
    #expect(MenuLanguage.preference("fr") == .english)
    #expect(MenuLanguage.preference("zh-Hans") == .simplifiedChinese)
    #expect(MenuLanguage.preference("en") == .english)
}

@Test func customIdleDurationAcceptsEitherUnitWithoutLosingPrecision() {
    #expect(IdleDuration.custom(" 10 ", unit: .hours) == IdleDuration(count: 10, unit: .hours))
    #expect(IdleDuration.custom("75", unit: .minutes) == IdleDuration(count: 75, unit: .minutes))
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
