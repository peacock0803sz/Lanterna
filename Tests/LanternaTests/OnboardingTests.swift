@testable import Lanterna
import Testing

/// When the onboarding window opens is a property of the launch-time answers,
/// not of the moment it is asked: deciding it from anything later would let a
/// grant given mid-run change what this run does.
@MainActor
struct OnboardingTests {
    @Test(arguments: [
        // Nothing granted: the guide opens.
        (PermissionState(accessibilityGranted: false, inputMonitoringGranted: false), nil, true),
        // Either half missing: the guide still opens, naming only what is missing.
        (PermissionState(accessibilityGranted: false, inputMonitoringGranted: true), nil, true),
        (PermissionState(accessibilityGranted: true, inputMonitoringGranted: false), nil, true),
        // Everything granted: nothing stands in the way.
        (PermissionState(accessibilityGranted: true, inputMonitoringGranted: true), nil, false),
        // The fixture needs no permission, so the guide never opens for it.
        (PermissionState(accessibilityGranted: false, inputMonitoringGranted: false), 0, false),
        (PermissionState(accessibilityGranted: false, inputMonitoringGranted: false), 18, false),
        (PermissionState(accessibilityGranted: true, inputMonitoringGranted: true), 3, false),
    ])
    func theGuideOpensExactlyWhenSomethingIsMissing(
        state: PermissionState, sampleCount: Int?, opens: Bool
    ) {
        #expect(OnboardingNeed.isNeeded(state: state, sampleCount: sampleCount) == opens)
    }

    /// The guide names only what is missing, in a fixed order. Screen
    /// Recording is never among them: this app must not ask for it.
    @Test(arguments: [
        (
            PermissionState(accessibilityGranted: false, inputMonitoringGranted: false),
            ["Accessibility", "Input Monitoring"]
        ),
        (PermissionState(accessibilityGranted: false, inputMonitoringGranted: true), ["Accessibility"]),
        (PermissionState(accessibilityGranted: true, inputMonitoringGranted: false), ["Input Monitoring"]),
        (PermissionState(accessibilityGranted: true, inputMonitoringGranted: true), []),
    ])
    func theGuideNamesOnlyWhatIsMissing(state: PermissionState, names: [String]) {
        #expect(MissingPermission.list(for: state).map(\.name) == names)
    }

    /// The headline names what is actually broken. Without Accessibility no
    /// list can be built; without only Input Monitoring the list still works
    /// but Command release goes unnoticed. Nothing missing is an all-clear,
    /// never an empty guide.
    @Test(arguments: [
        (
            PermissionState(accessibilityGranted: false, inputMonitoringGranted: false),
            "Lanterna cannot list windows yet"
        ),
        (
            PermissionState(accessibilityGranted: false, inputMonitoringGranted: true),
            "Lanterna cannot list windows yet"
        ),
        (
            PermissionState(accessibilityGranted: true, inputMonitoringGranted: false),
            "Lanterna cannot notice Command being released"
        ),
        (
            PermissionState(accessibilityGranted: true, inputMonitoringGranted: true),
            "Lanterna has the permissions it needs"
        ),
    ])
    func theHeadlineMatchesWhatIsBroken(state: PermissionState, headline: String) {
        let view = OnboardingView(missing: MissingPermission.list(for: state), opener: { _ in true })
        #expect(view.headline == headline)
    }
}
