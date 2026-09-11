import Carbon.HIToolbox

/// What one round of hotkey registration achieved.
///
/// The two combinations are registered separately and either can fail on its
/// own, so the result is a pair of lists rather than a yes or no. This is also
/// the only place the launch diagnostics line is worded, which keeps the shape
/// of that line testable while the registration itself is not.
struct HotkeyRegistrationOutcome: Sendable {
    /// A combination the system would not hand over, and the status it gave.
    struct Failure: Sendable {
        let combination: HotkeyCombination
        let status: OSStatus
    }

    let registered: [HotkeyCombination]
    let failures: [Failure]

    /// Nothing was registered, so there is no way left to reach the switcher
    /// and no reason to stay running.
    var isTotalFailure: Bool {
        registered.isEmpty
    }

    /// The one line written after registration: what was taken, what was not
    /// and why, and whether that leaves anything to run for.
    var summaryLine: String {
        var segments: [String] = []
        if !registered.isEmpty {
            segments.append("registered " + registered.map(\.name).joined(separator: ", "))
        }
        if !failures.isEmpty {
            let reasons = failures.map { "\($0.combination.name) (error \($0.status))" }
            segments.append("could not register " + reasons.joined(separator: ", "))
        }
        if isTotalFailure {
            segments.append("no hotkey registered, exiting")
        }
        return segments.joined(separator: "; ")
    }
}
