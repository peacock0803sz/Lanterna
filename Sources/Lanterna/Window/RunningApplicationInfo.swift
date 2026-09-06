import AppKit

/// One running application the switcher may list windows for.
///
/// Built on the main thread before any window is read, and kept there by
/// `@MainActor` on this type: the `NSRunningApplication` it is built from and
/// the `NSImage` it holds are used from the main thread only, by policy, not
/// because they could not be sent. Only the process identifier travels to the
/// reading threads; the name and icon wait here and are attached to the rows
/// afterwards.
@MainActor
struct RunningApplicationInfo {
    let processIdentifier: pid_t
    let name: String
    let bundleIdentifier: String?
    let icon: NSImage

    /// Applications that appear in the Dock and the system switcher, in the
    /// order the workspace reports. Ordering for display happens later, from
    /// the process identifier, because this order is not guaranteed.
    static func regularApplications() -> [RunningApplicationInfo] {
        let currentProcess = getpid()
        return NSWorkspace.shared.runningApplications.compactMap { application in
            guard isCandidate(
                activationPolicy: application.activationPolicy,
                processIdentifier: application.processIdentifier,
                currentProcess: currentProcess
            ) else {
                return nil
            }
            return RunningApplicationInfo(
                processIdentifier: application.processIdentifier,
                name: displayName(
                    localizedName: application.localizedName,
                    bundleURL: application.bundleURL,
                    executableURL: application.executableURL,
                    processIdentifier: application.processIdentifier
                ),
                bundleIdentifier: application.bundleIdentifier,
                icon: resolvedIcon(application.icon)
            )
        }
    }

    /// Menu-bar utilities and background helpers own no window a user switches
    /// to, and the switcher's own panel must not list itself.
    nonisolated static func isCandidate(
        activationPolicy: NSApplication.ActivationPolicy,
        processIdentifier: pid_t,
        currentProcess: pid_t
    ) -> Bool {
        activationPolicy == .regular && processIdentifier != currentProcess
    }

    /// The name shown in the Dock, or the closest thing to it that can be
    /// found. Never empty: a row without a name is worse than a row named after
    /// its process, and the name is also what an untitled window shows.
    nonisolated static func displayName(
        localizedName: String?,
        bundleURL: URL?,
        executableURL: URL?,
        processIdentifier: pid_t
    ) -> String {
        if let localizedName, !localizedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localizedName
        }
        if let name = bundleURL?.deletingPathExtension().lastPathComponent, !name.isEmpty {
            return name
        }
        if let name = executableURL?.lastPathComponent, !name.isEmpty {
            return name
        }
        return "pid \(processIdentifier)"
    }

    /// The icon slot is never empty, so an application that reports no icon
    /// shares the generic one.
    static func resolvedIcon(_ icon: NSImage?) -> NSImage {
        icon ?? AppIconResolver.placeholder
    }
}
