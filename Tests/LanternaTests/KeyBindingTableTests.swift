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
        #expect(accepted[.show] == [key(kVK_Tab, [.command, .shift])])
        #expect(acceptedIssues.isEmpty)
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
        // commit takes Cmd+W, which closeWindow holds by default.
        let (table, issues) = KeyBindingResolver.resolve(
            [.commit: [raw(kVK_ANSI_W, "cmd")]], order: [.commit]
        )
        #expect(!table[.commit].contains(key(kVK_ANSI_W, .command)))
        #expect(table[.closeWindow] == KeyBindingTable.defaults[.closeWindow])
        #expect(issues.count == 1)
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

    @Test func customBeatsDefaultAndLoserFallsBack() {
        // commit takes Cmd+W from closeWindow's defaults; commit loses the
        // key and falls back to its own defaults, which are free.
        let (table, _) = KeyBindingResolver.resolve(
            [.commit: [raw(kVK_ANSI_W, "cmd")]], order: [.commit]
        )
        #expect(table[.commit] == KeyBindingTable.defaults[.commit])
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
