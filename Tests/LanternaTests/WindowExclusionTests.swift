import AppKit
@testable import Lanterna
import Testing

/// Rows with distinct apps and titles, because exclusion reads both.
///
/// Bundle ids ride along where the judgement needs them; a nil bundle id
/// exercises the display-name path on its own.
@MainActor
private func exclusionRow(
    appName: String,
    bundleIdentifier: String?,
    windowTitle: String,
    windowID: CGWindowID
) -> WindowItem {
    WindowItem(
        id: WindowItem.Identifier(windowID: windowID),
        ownerProcessIdentifier: 0,
        appName: appName,
        bundleIdentifier: bundleIdentifier,
        windowTitle: windowTitle,
        kind: .standard,
        isMinimized: false,
        icon: NSImage(size: NSSize(width: 1, height: 1))
    )
}

/// The exclusion contract, held without any window server.
///
/// Every case here runs against rows made by hand
/// (contracts/exclusions.md): which rows leave the list is decided by the
/// test, never by watching real windows.
@MainActor
struct WindowExclusionTests {
    private var rows: [WindowItem] {
        [
            exclusionRow(
                appName: "1Password",
                bundleIdentifier: "com.1password.1password",
                windowTitle: "Mini",
                windowID: 1
            ),
            exclusionRow(
                appName: "1Password",
                bundleIdentifier: "com.1password.1password",
                windowTitle: "My Vault",
                windowID: 2
            ),
            exclusionRow(
                appName: "Installer",
                bundleIdentifier: "com.apple.Installer",
                windowTitle: "Install progress",
                windowID: 3
            ),
            exclusionRow(
                appName: "Notes",
                bundleIdentifier: nil,
                windowTitle: "Mini",
                windowID: 4
            ),
        ]
    }

    private func rules(_ entries: [ExclusionEntry]) -> [ExclusionRule] {
        WindowExclusion.compile(entries).rules
    }

    /// No rules returns the input unchanged, without judging a row.
    @Test func emptyRulesReturnTheInputUnchanged() {
        #expect(WindowExclusion.excluding(rows, rules: []).map(\.id) == rows.map(\.id))
    }

    /// Excluding keeps the order it found; it never sorts.
    @Test func excludingKeepsTheInputOrder() {
        let remaining = WindowExclusion.excluding(
            rows,
            rules: rules([ExclusionEntry(app: "NoSuchApp.*", titlePattern: "zzz")])
        )
        #expect(remaining.map(\.id) == rows.map(\.id))
    }

    /// A bundle id match excludes, ignoring case.
    @Test func bundleIdentifierMatchExcludes() {
        let remaining = WindowExclusion.excluding(
            rows,
            rules: rules([ExclusionEntry(app: "COM.1PASSWORD.1PASSWORD", titlePattern: "Mini")])
        )
        #expect(remaining.map(\.id) == [rows[1].id, rows[2].id, rows[3].id])
    }

    /// A display-name pattern match excludes.
    @Test func displayNamePatternMatchExcludes() {
        let remaining = WindowExclusion.excluding(
            rows,
            rules: rules([ExclusionEntry(app: "Install.*", titlePattern: "progress")])
        )
        #expect(remaining.map(\.id) == [rows[0].id, rows[1].id, rows[3].id])
    }

    /// Both halves must match; one half alone excludes nothing.
    @Test func bothAppAndTitleMustMatch() {
        let appOnly = WindowExclusion.excluding(
            rows,
            rules: rules([ExclusionEntry(app: "com.1password.1password", titlePattern: "zzz")])
        )
        #expect(appOnly.map(\.id) == rows.map(\.id))
        let titleOnly = WindowExclusion.excluding(
            rows,
            rules: rules([ExclusionEntry(app: "NoSuchApp.*", titlePattern: "Mini")])
        )
        #expect(titleOnly.map(\.id) == rows.map(\.id))
    }

    /// A title substring match ignores case.
    @Test func titleSubstringIgnoresCase() {
        let remaining = WindowExclusion.excluding(
            rows,
            rules: rules([ExclusionEntry(app: "com.apple.Installer", titlePattern: "PROGRESS")])
        )
        #expect(remaining.map(\.id) == [rows[0].id, rows[1].id, rows[3].id])
    }

    /// A nil bundle id still judges by the display name.
    @Test func nilBundleIdentifierFallsBackToDisplayName() {
        let remaining = WindowExclusion.excluding(
            rows,
            rules: rules([ExclusionEntry(app: "^Notes$", titlePattern: "Mini")])
        )
        #expect(remaining.map(\.id) == [rows[0].id, rows[1].id, rows[2].id])
    }
}
