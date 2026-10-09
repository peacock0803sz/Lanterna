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

/// Main-block ANSI key codes paired with the US keycaps they display as.
private let ansiLabels: [(Int, String)] = [
  (kVK_ANSI_A, "A"),
  (kVK_ANSI_B, "B"),
  (kVK_ANSI_C, "C"),
  (kVK_ANSI_D, "D"),
  (kVK_ANSI_E, "E"),
  (kVK_ANSI_F, "F"),
  (kVK_ANSI_G, "G"),
  (kVK_ANSI_H, "H"),
  (kVK_ANSI_I, "I"),
  (kVK_ANSI_J, "J"),
  (kVK_ANSI_K, "K"),
  (kVK_ANSI_L, "L"),
  (kVK_ANSI_M, "M"),
  (kVK_ANSI_N, "N"),
  (kVK_ANSI_O, "O"),
  (kVK_ANSI_P, "P"),
  (kVK_ANSI_Q, "Q"),
  (kVK_ANSI_R, "R"),
  (kVK_ANSI_S, "S"),
  (kVK_ANSI_T, "T"),
  (kVK_ANSI_U, "U"),
  (kVK_ANSI_V, "V"),
  (kVK_ANSI_W, "W"),
  (kVK_ANSI_X, "X"),
  (kVK_ANSI_Y, "Y"),
  (kVK_ANSI_Z, "Z"),
  (kVK_ANSI_0, "0"),
  (kVK_ANSI_1, "1"),
  (kVK_ANSI_2, "2"),
  (kVK_ANSI_3, "3"),
  (kVK_ANSI_4, "4"),
  (kVK_ANSI_5, "5"),
  (kVK_ANSI_6, "6"),
  (kVK_ANSI_7, "7"),
  (kVK_ANSI_8, "8"),
  (kVK_ANSI_9, "9"),
  (kVK_ANSI_Equal, "="),
  (kVK_ANSI_Minus, "-"),
  (kVK_ANSI_RightBracket, "]"),
  (kVK_ANSI_LeftBracket, "["),
  (kVK_ANSI_Quote, "'"),
  (kVK_ANSI_Semicolon, ";"),
  (kVK_ANSI_Backslash, "\\"),
  (kVK_ANSI_Comma, ","),
  (kVK_ANSI_Slash, "/"),
  (kVK_ANSI_Period, "."),
  (kVK_ANSI_Grave, "`"),
]

// MARK: - KeyBindingTableTests

struct KeyBindingTableTests {
  @Test
  func defaultsCoverEveryAction() {
    let table = KeyBindingTable.defaults
    #expect(table.keys.count == KeyBindingAction.allCases.count)
    #expect(table[.commit].count == 2)
    #expect(table[.cancel].count == 2)
    #expect(table[.show] == [key(kVK_Tab, .command)])
    #expect(table[.closeWindow] == [key(kVK_ANSI_W, .command)])
    #expect(table[.toggleScope] == [key(kVK_ANSI_Slash, .command)])
    #expect(
      table[.next]
        == [key(kVK_DownArrow), key(kVK_ANSI_J), key(kVK_ANSI_N)]
    )
    #expect(
      table[.previous]
        == [key(kVK_UpArrow), key(kVK_ANSI_K), key(kVK_ANSI_P)]
    )
    #expect(table[.startFiltering] == [key(kVK_ANSI_S)])
    #expect(table[.openSettings] == [key(kVK_ANSI_Comma, .command)])
  }

  /// The scope key is held to a modifier, the way the window operations
  /// are: a bare key there would never reach the query.
  @Test
  func theScopeKeyNeedsAModifier() {
    #expect(KeyBindingAction.toggleScope.mode == .guarded)
    #expect(KeyBindingTable.defaults[.toggleScope].first?.displayName == "Cmd+/")
  }

  @Test
  func displayNamesSpellModifiersFirst() {
    #expect(KeyBindingTable.defaults[.show].first?.displayName == "Cmd+Tab")
    #expect(KeyBindingTable.defaults[.showReverse].first?.displayName == "Shift+Cmd+Tab")
    #expect(KeyBindingTable.defaults[.commit].first?.displayName == "Return")
    #expect(KeyBindingTable.defaults[.cancel].first?.displayName == "Esc")
    #expect(KeyBindingTable.defaults[.closeWindow].first?.displayName == "Cmd+W")
    #expect(KeyBindingTable.defaults[.quitApplication].first?.displayName == "Cmd+Q")
    #expect(KeyBindingTable.defaults[.hideApplication].first?.displayName == "Cmd+H")
    #expect(KeyBindingTable.defaults[.minimizeWindow].first?.displayName == "Cmd+M")
    #expect(ResolvedKey(keyCode: UInt16(kVK_F5), modifiers: []).displayName == "key 96")
    #expect(ResolvedKey(keyCode: UInt16(kVK_ANSI_Keypad1), modifiers: []).displayName == "Keypad 1")
  }

  @Test(arguments: ansiLabels)
  func mainBlockANSIKeysSpellUSKeycaps(code: Int, label: String) {
    #expect(ResolvedKey(keyCode: UInt16(code), modifiers: []).displayName == label)
  }

  @Test
  func modeAllowsBareAndRefusesShiftOnly() {
    #expect(KeyBindingTable.allows(modifiers: [], mode: .bare))
    #expect(!KeyBindingTable.allows(modifiers: [], mode: .global))
    #expect(!KeyBindingTable.allows(modifiers: .shift, mode: .guarded))
    #expect(KeyBindingTable.allows(modifiers: [.command, .shift], mode: .global))
  }

  @Test
  func holdersSkipSelfAndExcusedPair() {
    let table = KeyBindingTable.defaults
    let escape = ResolvedKey(keyCode: UInt16(kVK_Escape), modifiers: [])
    #expect(table.holders(of: escape, except: .cancel) == [])
    #expect(table.holders(of: escape, except: .next) == [.cancel, .clearQuery])
  }

  @Test
  func issueWordsDiagnosticsLine() {
    let issue = KeyBindingIssue(
      action: .commit,
      reason: .conflict,
      detail: "keyCode 13 is already taken"
    )
    #expect(
      issue.diagnosticsLine
        == "config keybinding (commit conflict: keyCode 13 is already taken); using default"
    )
  }

  @Test
  func absentSectionMeansDefaultsWithoutIssues() {
    let (table, issues) = KeyBindingResolver.resolve([:], order: [])
    #expect(table == .defaults)
    #expect(issues.isEmpty)
  }

  @Test
  func negativeKeyCodeIsDropped() {
    let (table, issues) = KeyBindingResolver.resolve(
      [.next: [raw(-1, "cmd")]],
      order: [.next]
    )
    #expect(table[.next] == KeyBindingTable.defaults[.next])
    #expect(issues.count == 1)
    #expect(issues[0].action == .next)
    #expect(issues[0].reason == .invalid)
  }

  @Test
  func unknownModifierWordIsDropped() {
    let (table, issues) = KeyBindingResolver.resolve(
      [.next: [raw(kVK_DownArrow, "super")]],
      order: [.next]
    )
    #expect(table[.next] == KeyBindingTable.defaults[.next])
    #expect(issues.count == 1)
    #expect(issues[0].reason == .invalid)
  }

  @Test
  func shiftOnlyGlobalIsRejectedButCmdShiftPasses() {
    let (rejected, rejectedIssues) = KeyBindingResolver.resolve(
      [.show: [raw(kVK_Tab, "shift")]],
      order: [.show]
    )
    #expect(rejected[.show] == KeyBindingTable.defaults[.show])
    #expect(rejectedIssues.count == 1)

    let (accepted, acceptedIssues) = KeyBindingResolver.resolve(
      [.show: [raw(kVK_Tab, "cmd", "shift")]],
      order: [.show]
    )
    // The customized show displaces the untouched showReverse default.
    #expect(accepted[.show] == [key(kVK_Tab, [.command, .shift])])
    #expect(accepted[.showReverse] == [])
    #expect(acceptedIssues.count == 2)
    #expect(acceptedIssues[0].action == .showReverse)
    #expect(acceptedIssues[0].reason == .conflict)
    #expect(acceptedIssues[1].action == .showReverse)
    #expect(acceptedIssues[1].detail.contains("unbound"))
  }

  @Test
  func bareActionsAcceptBareKeys() {
    let (table, issues) = KeyBindingResolver.resolve(
      [.next: [raw(kVK_DownArrow)]],
      order: [.next]
    )
    #expect(table[.next] == [key(kVK_DownArrow)])
    #expect(issues.isEmpty)
  }

  @Test
  func bareWindowOperationIsRejected() {
    let (table, issues) = KeyBindingResolver.resolve(
      [.closeWindow: [raw(kVK_ANSI_W)]],
      order: [.closeWindow]
    )
    #expect(table[.closeWindow] == KeyBindingTable.defaults[.closeWindow])
    #expect(issues.count == 1)
    #expect(issues[0].reason == .invalid)
  }

  @Test
  func laterPanelCustomizationLosesTheSharedKey() {
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

  @Test
  func panelCustomizationLosesToGlobalDefault() {
    // commit takes Cmd+Tab, which show holds by default: invocation
    // wins, and commit falls back to its own free defaults.
    let (table, issues) = KeyBindingResolver.resolve(
      [.commit: [raw(kVK_Tab, "cmd")]],
      order: [.commit]
    )
    #expect(table[.commit] == KeyBindingTable.defaults[.commit])
    #expect(table[.show] == KeyBindingTable.defaults[.show])
    #expect(issues.count == 1)
    #expect(issues[0].action == .commit)
    #expect(issues[0].reason == .conflict)
  }

  @Test
  func laterGlobalCustomizationLosesToEarlierOne() {
    let (table, issues) = KeyBindingResolver.resolve(
      [
        .show: [raw(kVK_Space, "cmd")],
        .showFilter: [raw(kVK_Space, "cmd")],
      ],
      order: [.show, .showFilter]
    )
    #expect(table[.show] == [key(kVK_Space, .command)])
    #expect(!table[.showFilter].contains(key(kVK_Space, .command)))
    #expect(table[.showFilter] == [])
    #expect(issues.count == 2)
    #expect(issues[0].action == .showFilter)
    #expect(issues[1].action == .showFilter)
    #expect(issues[1].detail.contains("unbound"))
  }

  @Test
  func clearQueryAndCancelMayShareKeys() {
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

  @Test
  func panelCustomizationDisplacesUntouchedDefaults() {
    // commit takes Cmd+W, which closeWindow holds only by default:
    // the untouched default gives way and ends up unbound.
    let (table, issues) = KeyBindingResolver.resolve(
      [.commit: [raw(kVK_ANSI_W, "cmd")]],
      order: [.commit]
    )
    #expect(table[.commit] == [key(kVK_ANSI_W, .command)])
    #expect(table[.closeWindow] == [])
    #expect(issues.count == 2)
    #expect(issues[0].action == .closeWindow)
    #expect(issues[0].reason == .conflict)
    #expect(issues[1].action == .closeWindow)
    #expect(issues[1].detail.contains("unbound"))
  }

  @Test
  func refillWaitsForLaterCustomizationsInTier() {
    // closeWindow's entry is invalid, so it refills only after
    // quitApplication has claimed Cmd+W: the refill must not steal it.
    let (table, issues) = KeyBindingResolver.resolve(
      [
        .closeWindow: [raw(-1, "cmd")],
        .quitApplication: [raw(kVK_ANSI_W, "cmd")],
      ],
      order: [.closeWindow, .quitApplication]
    )
    #expect(table[.quitApplication] == [key(kVK_ANSI_W, .command)])
    #expect(table[.closeWindow] == [])
    #expect(issues.count == 2)
    #expect(issues[1].action == .closeWindow)
    #expect(issues[1].detail.contains("unbound"))
  }

  @Test
  func declarationOrderSkipsBracesInsideStrings() {
    let text = "{\"keybindings\": {\"commit\": [{\"keyCode\": 1, \"modifiers\": [\"c}\"]}], "
      + "\"next\": [{\"keyCode\": 125, \"modifiers\": []}]}}"
    #expect(KeyBindingResolver.declarationOrder(in: text) == [.commit, .next])
  }

  @Test
  func declarationOrderSkipsEscapedQuotes() {
    let text = #"{"keybindings": {"commit": [{"keyCode": 1, "modifiers": ["c\"}"]}], "next": []}}"#
    #expect(KeyBindingResolver.declarationOrder(in: text) == [.commit, .next])
  }

  @Test
  func declarationOrderIgnoresKeybindingsValue() {
    let text = "{\"note\": \"keybindings\", \"keybindings\": "
      + "{\"next\": [{\"keyCode\": 125, \"modifiers\": []}]}}"
    #expect(KeyBindingResolver.declarationOrder(in: text) == [.next])
  }

  @Test
  func duplicateKeysWithinOneActionCountOnce() {
    let (table, issues) = KeyBindingResolver.resolve(
      [.next: [raw(kVK_DownArrow), raw(kVK_DownArrow)]],
      order: [.next]
    )
    #expect(table[.next] == [key(kVK_DownArrow)])
    #expect(issues.isEmpty)
  }

  @Test
  func keyCodeOutside127IsDropped() {
    let (rejected, rejectedIssues) = KeyBindingResolver.resolve(
      [.next: [raw(128)]],
      order: [.next]
    )
    #expect(rejected[.next] == KeyBindingTable.defaults[.next])
    #expect(rejectedIssues.count == 1)
    #expect(rejectedIssues[0].reason == .invalid)
    let (accepted, acceptedIssues) = KeyBindingResolver.resolve(
      [.next: [raw(127)]],
      order: [.next]
    )
    #expect(accepted[.next] == [key(127)])
    #expect(acceptedIssues.isEmpty)
  }

  @Test
  func assignmentRefusalSpellsTheRules() {
    #expect(KeyBindingTable.refusal(assigning: key(96), to: .next, in: .defaults) == nil)
    #expect(KeyBindingTable.refusal(
      assigning: key(kVK_Tab, .shift),
      to: .show,
      in: .defaults
    ) == .needsModifiers)
    #expect(KeyBindingTable.refusal(
      assigning: key(kVK_DownArrow),
      to: .next,
      in: .defaults
    ) == .alreadyHeld)
  }

  @Test
  func assignmentRefusalReadsEmptiesAsDefaults() {
    var emptied = KeyBindingTable.defaults
    emptied.keys[.next] = []
    #expect(KeyBindingTable.refusal(
      assigning: key(kVK_DownArrow),
      to: .next,
      in: emptied
    ) == .alreadyHeld)
    var displaced = KeyBindingTable.defaults
    displaced.keys[.closeWindow] = []
    #expect(KeyBindingTable.refusal(
      assigning: key(kVK_ANSI_W, .command),
      to: .quitApplication,
      in: displaced
    ) == .heldBy([.closeWindow]))
  }

  @Test
  func assignmentRefusalExcusesClearAndCancel() {
    var table = KeyBindingTable.defaults
    table.keys[.cancel] = [key(kVK_ANSI_Period, .command)]
    #expect(KeyBindingTable.refusal(
      assigning: key(kVK_Escape),
      to: .cancel,
      in: table
    ) == nil)
    #expect(KeyBindingTable.refusal(
      assigning: key(kVK_Escape),
      to: .next,
      in: .defaults
    ) == .heldBy([.cancel, .clearQuery]))
  }

  @Test
  func bareAnswersFollowFiltering() {
    let bare = key(kVK_ANSI_J)
    let guarded = key(kVK_ANSI_J, .command)
    func stroke(_ modifiers: NSEvent.ModifierFlags, _ characters: String) -> PanelKeystroke {
      PanelKeystroke(
        keyCode: UInt16(kVK_ANSI_J),
        modifiers: modifiers,
        isARepeat: false,
        characters: characters
      )
    }
    #expect(guarded.answers(stroke(.command, "j"), filtering: false))
    #expect(guarded.answers(stroke(.command, "j"), filtering: true))
    #expect(guarded.answers(stroke(.command, ""), filtering: true))
    #expect(bare.answers(stroke([], ""), filtering: false))
    #expect(bare.answers(stroke([], "/"), filtering: false))
    #expect(bare.answers(stroke([], "j"), filtering: false))
    #expect(bare.answers(stroke([], ""), filtering: true))
    #expect(bare.answers(stroke([], "/"), filtering: true))
    #expect(!bare.answers(stroke([], "j"), filtering: true))
    #expect(bare.answers(stroke(.command, "j"), filtering: false))
    #expect(!bare.answers(stroke(.command, "j"), filtering: true))
  }

  @Test
  func matchesWithoutFilteringKeepsFiltering() {
    var table = KeyBindingTable.defaults
    table.keys[.next] = [key(kVK_ANSI_J)]
    let press = PanelKeystroke(
      keyCode: UInt16(kVK_ANSI_J),
      modifiers: [],
      isARepeat: false,
      characters: "j"
    )
    #expect(!table.matches(press, action: .next))
    #expect(table.matches(press, action: .next, filtering: false))
  }

  @Test
  func settingsAssignmentRefusalSpellsTheRules() {
    #expect(KeyBindingTable.refusal(
      assigning: key(kVK_ANSI_Comma),
      to: .openSettings,
      in: .defaults
    ) == .needsModifiers)
    #expect(KeyBindingTable.refusal(
      assigning: key(kVK_ANSI_F),
      to: .startFiltering,
      in: .defaults
    ) == nil)
    #expect(KeyBindingTable.refusal(
      assigning: key(kVK_ANSI_S),
      to: .startFiltering,
      in: .defaults
    ) == .alreadyHeld)
  }

  @Test
  func kanaIndependentByConstruction() {
    // Resolution never sees characters: the same physical key resolves
    // the same way whatever the input source produced.
    let (table, issues) = KeyBindingResolver.resolve(
      [.next: [raw(kVK_DownArrow)]],
      order: [.next]
    )
    #expect(table[.next] == [key(kVK_DownArrow)])
    #expect(issues.isEmpty)
  }
}
