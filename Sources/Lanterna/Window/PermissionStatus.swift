import CoreGraphics

/// The two permissions this process asks about, as one launch-time answer.
///
/// Read once per launch rather than per press: a grant given while the app
/// runs takes effect on the next run, so asking again mid-run would answer a
/// question nothing is allowed to act on.
struct PermissionState: Equatable, Sendable {
    /// Whether Accessibility is granted.
    let accessibilityGranted: Bool
    /// Whether Input Monitoring suffices for a tap.
    let inputMonitoringGranted: Bool
}

/// Decides whether the onboarding window opens.
///
/// A pure function of the launch-time answers rather than a reading of the
/// system, so every combination is answerable from a test without putting up
/// a system dialog.
enum OnboardingNeed {
    /// The fixture needs no permission, so a run showing sample entries never
    /// opens the guide whatever the system answers.
    static func isNeeded(state: PermissionState, sampleCount: Int?) -> Bool {
        if sampleCount != nil {
            return false
        }
        return !state.accessibilityGranted || !state.inputMonitoringGranted
    }
}

/// Reads the launch-time answers from the system.
///
/// A protocol rather than a direct call, so the launch wiring can be shown a
/// fixed answer in a test. The only production reader is below.
protocol PermissionReading: Sendable {
    /// The one reading this launch gets. Main-actor isolated because the
    /// system answers belong to it.
    @MainActor func currentState() -> PermissionState
}

/// The production reader.
///
/// Asks without prompting: the fixture launch needs no permission at all,
/// and the window-list path already prompts where a prompt is due. Prompting
/// here would put up a dialog for a `--sample-count` run and ask twice on an
/// ordinary run missing Accessibility.
@MainActor
struct SystemPermissionReader: PermissionReading {
    func currentState() -> PermissionState {
        PermissionState(
            accessibilityGranted: AccessibilityPermission.isTrusted(promptingIfNeeded: false),
            inputMonitoringGranted: CGPreflightListenEventAccess()
        )
    }
}
