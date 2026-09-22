import AppKit

/// What a commit takes: the row it named, as identity, owner and names.
///
/// A value, not the row itself. `WindowItem` carries an `NSImage` and so is
/// neither `Equatable` nor `Sendable`, while switching needs only who owns
/// which window and what to call it on the log line. The names travel along
/// for the wording; nothing that decides is read off them.
struct ActivationTarget: Equatable, Sendable {
    let id: WindowItem.Identifier
    let ownerProcessIdentifier: pid_t
    let appName: String
    let displayTitle: String
    /// As of the appearance that named it, for the log line only. Whether to
    /// unminimize is never decided off this: unminimizing is written
    /// unconditionally, a write with no effect when there is nothing to undo.
    let isMinimized: Bool
}

/// Why a switch did not happen. The smallest vocabulary that tells the four
/// apart on the log line; anything else goes in `other` until it earns a case.
enum ActivationFailure: Equatable, Sendable {
    case windowGone
    case applicationGone
    case timedOut
    case other(reason: String)
}

/// What trying a target came to.
enum ActivationOutcome: Equatable, Sendable {
    case switched
    case failed(ActivationFailure)
}

/// The one entrance the commit paths call. Takes a single target rather than
/// a list, so resolving off a fresher list at commit time has nowhere to go.
protocol WindowSwitching: Sendable {
    func switchTo(_ target: ActivationTarget) -> ActivationOutcome
}
