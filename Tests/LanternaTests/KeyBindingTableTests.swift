import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Builds a raw binding the way the config file spells one.
private func raw(_ keyCode: Int, _ modifiers: String...) -> RawKeyBinding {
    RawKeyBinding(keyCode: keyCode, modifiers: modifiers)
}

/// The resolved form of a raw binding with valid modifiers.
private func key(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> ResolvedKey {
    ResolvedKey(keyCode: UInt16(keyCode), modifiers: modifiers)
}

struct KeyBindingTableTests {
    @Test func defaultsCoverEveryAction() {
        let table = KeyBindingTable.defaults
        #expect(table.keys.count == KeyBindingAction.allCases.count)
        #expect(table[.commit].count == 2)
        #expect(table[.cancel].count == 2)
        #expect(table[.show] == [key(kVK_Tab, .command)])
        #expect(table[.closeWindow] == [key(kVK_ANSI_W, .command)])
    }

    @Test func displayNamesSpellModifiersFirst() {
        #expect(KeyBindingTable.defaults[.show].first?.displayName == "Cmd+Tab")
        #expect(KeyBindingTable.defaults[.showReverse].first?.displayName == "Shift+Cmd+Tab")
        #expect(KeyBindingTable.defaults[.commit].first?.displayName == "Return")
        #expect(KeyBindingTable.defaults[.cancel].first?.displayName == "Esc")
        #expect(ResolvedKey(keyCode: 96, modifiers: []).displayName == "key 96")
    }

    @Test func modeAllowsBareAndRefusesShiftOnly() {
        #expect(KeyBindingTable.allows(modifiers: [], mode: .bare))
        #expect(!KeyBindingTable.allows(modifiers: [], mode: .global))
        #expect(!KeyBindingTable.allows(modifiers: .shift, mode: .guarded))
        #expect(KeyBindingTable.allows(modifiers: [.command, .shift], mode: .global))
    }

    @Test func holdersSkipSelfAndExcusedPair() {
        let table = KeyBindingTable.defaults
        let escape = ResolvedKey(keyCode: UInt16(kVK_Escape), modifiers: [])
        #expect(table.holders(of: escape, except: .cancel) == [])
        #expect(table.holders(of: escape, except: .next) == [.cancel, .clearQuery])
    }

    @Test func issueWordsDiagnosticsLine() {
        let issue = KeyBindingIssue(
            action: .commit, reason: .conflict, detail: "keyCode 13 is already taken"
        )
        #expect(
            issue.diagnosticsLine
                == "config keybinding (commit conflict: keyCode 13 is already taken); using default"
        )
    }

    @Test func absentSectionMeansDefaultsWithoutIssues() {
        let (table, issues) = KeyBindingResolver.resolve([:], order: [])
        #expect(table == .defaults)
        #expect(issues.isEmpty)
    }

    @Test func negativeKeyCodeIsDropped() {
        let (table, issues) = KeyBindingResolver.resolve(
            [.next: [raw(-1, "cmd")]], order: [.next]
        )
        #expect(table[.next] == KeyBindingTable.defaults[.next])
        #expect(issues.count == 1)
        #expect(issues[0].action == .next)
        #expect(issues[0].reason == .invalid)
    }

    @Test func unknownModifierWordIsDropped() {
        let (table, issues) = KeyBindingResolver.resolve(
            [.next: [raw(kVK_DownArrow, "super")]], order: [.next]
        )
        #expect(table[.next] == KeyBindingTable.defaults[.next])
        #expect(issues.count == 1)
        #expect(issues[0].reason == .invalid)
    }

    @Test func shiftOnlyGlobalIsRejectedButCmdShiftPasses() {
        let (rejected, rejectedIssues) = KeyBindingResolver.resolve(
            [.show: [raw(kVK_Tab, "shift")]], order: [.show]
        )
        #expect(rejected[.show] == KeyBindingTable.defaults[.show])
        #expect(rejectedIssues.count == 1)

        let (accepted, acceptedIssues) = KeyBindingResolver.resolve(
            [.show: [raw(kVK_Tab, "cmd", "shift")]], order: [.show]
        )
        // The customized show displaces the untouched showReverse default.
        #expect(accepted[.show] == [key(kVK_Tab, [.command, .shift])])
        #expect(acceptedIssues.count == 1)
        #expect(acceptedIssues[0].action == .showReverse)
        #expect(acceptedIssues[0].reason == .conflict)
    }

    @Test func bareActionsAcceptBareKeys() {
        let (table, issues) = KeyBindingResolver.resolve(
            [.next: [raw(kVK_DownArrow)]], order: [.next]
        )
        #expect(table[.next] == [key(kVK_DownArrow)])
        #expect(issues.isEmpty)
    }

    @Test func bareWindowOperationIsRejected() {
        let (table, issues) = KeyBindingResolver.resolve(
            [.closeWindow: [raw(kVK_ANSI_W)]], order: [.closeWindow]
        )
        #expect(table[.closeWindow] == KeyBindingTable.defaults[.closeWindow])
        #expect(issues.count == 1)
        #expect(issues[0].reason == .invalid)
    }

    @Test func laterPanelCustomizationLosesTheSharedKey() {
        let shared = key(kVK_ANSI_W, .command)
        let (table, issues) = KeyBindingResolver.resolve(
            [
                .closeWindow: [raw(kVK_ANSI_W, "cmd")],
                .quitApplication: [raw(kVK_ANSI_W, "cmd")],
            ],
            order: [.closeWindow, .quitApplication]
        )
        #expect(table[.closeWindow] == [shared])
        #expect(!table[.quitApplication].contains(shared))
        #expect(issues.count == 1)
        #expect(issues[0].action == .quitApplication)
        #expect(issues[0].reason == .conflict)
    }

    @Test func panelCustomizationLosesToGlobalDefault() {
        // commit takes Cmd+Tab, which show holds by default: invocation
        // wins, and commit falls back to its own free defaults.
        let (table, issues) = KeyBindingResolver.resolve(
            [.commit: [raw(kVK_Tab, "cmd")]], order: [.commit]
        )
        #expect(table[.commit] == KeyBindingTable.defaults[.commit])
        #expect(table[.show] == KeyBindingTable.defaults[.show])
        #expect(issues.count == 1)
        #expect(issues[0].action == .commit)
        #expect(issues[0].reason == .conflict)
    }

    @Test func laterGlobalCustomizationLosesToEarlierOne() {
        let (table, issues) = KeyBindingResolver.resolve(
            [
                .show: [raw(kVK_Space, "cmd")],
                .showFilter: [raw(kVK_Space, "cmd")],
            ],
            order: [.show, .showFilter]
        )
        #expect(table[.show] == [key(kVK_Space, .command)])
        #expect(!table[.showFilter].contains(key(kVK_Space, .command)))
        #expect(issues.count == 1)
        #expect(issues[0].action == .showFilter)
    }

    @Test func clearQueryAndCancelMayShareKeys() {
        let shared = key(kVK_Escape)
        let (table, issues) = KeyBindingResolver.resolve(
            [
                .clearQuery: [raw(kVK_Escape)],
                .cancel: [raw(kVK_Escape)],
            ],
            order: [.clearQuery, .cancel]
        )
        #expect(table[.clearQuery] == [shared])
        #expect(table[.cancel] == [shared])
        #expect(issues.isEmpty)
    }

    @Test func panelCustomizationDisplacesUntouchedDefaults() {
        // commit takes Cmd+W, which closeWindow holds only by default:
        // the untouched default gives way and ends up unbound.
        let (table, issues) = KeyBindingResolver.resolve(
            [.commit: [raw(kVK_ANSI_W, "cmd")]], order: [.commit]
        )
        #expect(table[.commit] == [key(kVK_ANSI_W, .command)])
        #expect(table[.closeWindow] == [])
        #expect(issues.count == 1)
        #expect(issues[0].action == .closeWindow)
        #expect(issues[0].reason == .conflict)
    }

    @Test func kanaIndependentByConstruction() {
        // Resolution never sees characters: the same physical key resolves
        // the same way whatever the input source produced.
        let (table, issues) = KeyBindingResolver.resolve(
            [.next: [raw(kVK_DownArrow)]], order: [.next]
        )
        #expect(table[.next] == [key(kVK_DownArrow)])
        #expect(issues.isEmpty)
    }
}
