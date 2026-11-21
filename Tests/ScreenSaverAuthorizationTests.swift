import Testing

@Test func screenSaverConsentUsesTheDedicatedMainAppAction() {
    let notice = IdleLockNotice.forScreenSaver(.authorizationRequired, authorization: .notRequested)
    #expect(notice == .authorizeScreenSaver)
    #expect(notice?.action == .authorizeScreenSaver)
    #expect(IdleLockNotice.setupScreenSaver.action == .authorizeHelper)
}

@Test(arguments: [ScreenSaverStatus.authorizationRequired, .permissionDenied, .unavailable])
func waitingForScreenSaverConsentHidesTheAuthorizationButton(status: ScreenSaverStatus) {
    let notice = IdleLockNotice.forScreenSaver(status, authorization: .requesting)
    #expect(notice == .awaitingAutomation)
    #expect(notice?.action == nil)
}

@Test func deniedScreenSaverConsentOpensAutomationSettings() {
    let authorization = ScreenSaverAuthorizationState.finished(.denied)
    let denied = IdleLockNotice.forScreenSaver(.authorizationRequired, authorization: authorization)
    #expect(denied == .automationDenied)
    #expect(denied?.action == .openAutomationSettings)
    #expect(IdleLockNotice.forScreenSaver(.permissionDenied, authorization: .notRequested) == .automationDenied)
    #expect(IdleLockNotice.forScreenSaver(.unavailable, authorization: authorization) == .automationDenied)
}

@Test func failedScreenSaverConsentOffersAnExplicitRetry() {
    let notice = IdleLockNotice.forScreenSaver(.authorizationRequired, authorization: .finished(.failed))
    #expect(notice == .automationRequestFailed)
    #expect(notice?.action == .retryScreenSaverAuthorization)
}

@Test func grantedConsentWaitsForTheScreenSaverAgentToConfirmItsAccess() {
    let authorization = ScreenSaverAuthorizationState.finished(.granted)
    let notice = IdleLockNotice.forScreenSaver(.authorizationRequired, authorization: authorization)
    #expect(notice == .automationNotApplied)
    #expect(notice?.action == .openAutomationSettings)
    #expect(IdleLockNotice.forScreenSaver(.synchronized, authorization: authorization) == nil)
    #expect(IdleLockNotice.forScreenSaver(.unavailable, authorization: authorization)?.action == .openScreenSaverSettings)
}
