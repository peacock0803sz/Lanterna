import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// Decodes a config object holding the given keybindings fragment.
private func decodeBindings(_ fragment: String) -> Result<DecodedConfiguration, ConfigDecodeError> {
  AppConfiguration.decode(Data("{\"version\": 1, \"keybindings\": \(fragment)}".utf8))
}

// MARK: - KeyBindingConfigTests

struct KeyBindingConfigTests {
  @Test
  func customizedTableRoundTrips() {
    let first = decodeBindings(
      "{\"commit\": [{\"keyCode\": 96, \"modifiers\": []}]}"
    )
    guard case .success(let decoded) = first else {
      Issue.record("expected the custom section to decode")
      return
    }
    let encoded = AppConfiguration.encode(decoded.config)
    switch AppConfiguration.decode(encoded) {
    case .success(let again):
      #expect(again.config.keyBindings == decoded.config.keyBindings)
      #expect(again.keyBindingIssues.isEmpty)

    case .failure:
      Issue.record("expected the encoded table to decode cleanly")
    }
  }

  @Test
  func validSectionDecodes() {
    let result = decodeBindings(
      "{\"next\": [{\"keyCode\": \(kVK_DownArrow), \"modifiers\": []}]}"
    )
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings[.next]
        == [ResolvedKey(keyCode: UInt16(kVK_DownArrow), modifiers: [])])
      #expect(decoded.keyBindingIssues.isEmpty)

    case .failure:
      Issue.record("expected a valid section to decode")
    }
  }

  @Test
  func badEntryIsDroppedWhileRestSurvives() {
    let result = decodeBindings(
      "{\"next\": [{\"keyCode\": -1, \"modifiers\": []}], "
        + "\"previous\": [{\"keyCode\": \(kVK_UpArrow), \"modifiers\": []}]}"
    )
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings[.next] == KeyBindingTable.defaults[.next])
      #expect(decoded.config.keyBindings[.previous]
        == [ResolvedKey(keyCode: UInt16(kVK_UpArrow), modifiers: [])])
      #expect(decoded.keyBindingIssues.count == 1)

    case .failure:
      Issue.record("expected per-item recovery, not whole-file failure")
    }
  }

  @Test
  func unknownActionIsDropped() {
    let result = decodeBindings("{\"launch\": [{\"keyCode\": 48, \"modifiers\": [\"cmd\"]}]}")
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings == .defaults)
      #expect(decoded.keyBindingIssues.count == 1)

    case .failure:
      Issue.record("expected an unknown action to be dropped, not fatal")
    }
  }

  @Test
  func nonObjectSectionInvalidatesTheFile() {
    let result = decodeBindings("42")
    switch result {
    case .success:
      Issue.record("expected a non-object section to invalidate the file")
    case .failure(let error):
      #expect(error == .invalidValue(key: "keybindings"))
    }
  }

  @Test
  func laterWrittenActionLosesTheSharedKey() {
    let key = "{\"keyCode\": \(kVK_ANSI_W), \"modifiers\": [\"cmd\"]}"
    let first = decodeBindings(
      "{\"commit\": [\(key)], \"closeWindow\": [\(key)]}"
    )
    switch first {
    case .success(let decoded):
      // closeWindow is written later, so it loses Cmd+W.
      #expect(!decoded.config.keyBindings[.closeWindow].contains(
        ResolvedKey(keyCode: UInt16(kVK_ANSI_W), modifiers: .command)
      ))
      #expect(decoded.config.keyBindings[.commit].contains(
        ResolvedKey(keyCode: UInt16(kVK_ANSI_W), modifiers: .command)
      ))

    case .failure:
      Issue.record("expected file order to decide the conflict")
    }

    let second = decodeBindings(
      "{\"closeWindow\": [\(key)], \"commit\": [\(key)]}"
    )
    switch second {
    case .success(let decoded):
      #expect(!decoded.config.keyBindings[.commit].contains(
        ResolvedKey(keyCode: UInt16(kVK_ANSI_W), modifiers: .command)
      ))

    case .failure:
      Issue.record("expected file order to decide the conflict")
    }
  }

  @Test
  func emptyListMeansDefaults() {
    let result = decodeBindings("{\"next\": []}")
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings[.next] == KeyBindingTable.defaults[.next])
    case .failure:
      Issue.record("expected an empty list to mean defaults")
    }
  }

  @Test
  func entryWithExtraKeysIsDropped() {
    let result = decodeBindings(
      "{\"next\": [{\"keyCode\": \(kVK_DownArrow), \"modifiers\": [], \"characters\": \"a\"}]}"
    )
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings[.next] == KeyBindingTable.defaults[.next])
      #expect(decoded.keyBindingIssues.count == 1)

    case .failure:
      Issue.record("expected an entry with extra keys to be dropped")
    }
  }

  @Test
  func losingCustomizationSurvivesEncoding() throws {
    let key = "{\"keyCode\": \(kVK_ANSI_W), \"modifiers\": [\"cmd\"]}"
    let first = decodeBindings(
      "{\"commit\": [\(key)], \"closeWindow\": [\(key)]}"
    )
    guard case .success(let decoded) = first else {
      Issue.record("expected the clashing section to decode")
      return
    }
    let text = try #require(
      String(bytes: AppConfiguration.encode(decoded.config), encoding: .utf8)
    )
    #expect(text.contains("closeWindow"))
    #expect(text.contains("commit"))
    switch AppConfiguration.decode(Data(text.utf8)) {
    case .success(let again):
      #expect(again.config.keyBindingSection == decoded.config.keyBindingSection)
    case .failure:
      Issue.record("expected the encoded section to decode")
    }
  }

  @Test
  func settingsValuesKeepOnlyDifferences() {
    let defaults = SettingsValues.defaults.configuration(
      version: 1,
      sampleCount: nil,
      stopMonitorEverySeconds: nil
    )
    #expect(defaults.keyBindingSection == nil)
    var values = SettingsValues.defaults
    values.keyBindings.keys[.commit] = [ResolvedKey(keyCode: UInt16(kVK_Return), modifiers: [])]
    let customized = values.configuration(
      version: 1,
      sampleCount: nil,
      stopMonitorEverySeconds: nil
    )
    #expect(customized.keyBindingSection == [.commit: [RawKeyBinding(keyCode: kVK_Return, modifiers: [])]])
  }

  @Test
  func unrelatedSaveKeepsLosingEntry() {
    let key = "{\"keyCode\": \(kVK_Space), \"modifiers\": [\"cmd\"]}"
    let first = decodeBindings(
      "{\"show\": [\(key)], \"showFilter\": [\(key)]}"
    )
    guard case .success(let decoded) = first else {
      Issue.record("expected the clashing section to decode")
      return
    }
    #expect(decoded.config.keyBindings[.showFilter] == [])
    var values = SettingsValues.effective(from: decoded.config)
    values.appearanceMode = .dark
    let saved = values.configuration(
      version: 1,
      sampleCount: nil,
      stopMonitorEverySeconds: nil
    )
    #expect(saved.keyBindingSection == decoded.config.keyBindingSection)
    #expect(saved.keyBindingSection?[.showFilter] != nil)
  }

  @Test
  func newActionsRoundTrip() {
    let result = decodeBindings(
      "{\"startFiltering\": [{\"keyCode\": 3, \"modifiers\": []}], "
        + "\"openSettings\": [{\"keyCode\": \(kVK_ANSI_Comma), \"modifiers\": [\"cmd\"]}, "
        + "{\"keyCode\": \(kVK_ANSI_Comma), \"modifiers\": [\"opt\"]}]}"
    )
    guard case .success(let decoded) = result else {
      Issue.record("expected the new actions to decode")
      return
    }
    #expect(decoded.config.keyBindings[.startFiltering]
      == [ResolvedKey(keyCode: 3, modifiers: [])])
    #expect(decoded.config.keyBindings[.openSettings]
      == [
        ResolvedKey(keyCode: UInt16(kVK_ANSI_Comma), modifiers: .command),
        ResolvedKey(keyCode: UInt16(kVK_ANSI_Comma), modifiers: .option),
      ])
    #expect(decoded.keyBindingIssues.isEmpty)
    let encoded = AppConfiguration.encode(decoded.config)
    switch AppConfiguration.decode(encoded) {
    case .success(let again):
      #expect(again.config.keyBindings == decoded.config.keyBindings)
    case .failure:
      Issue.record("expected the encoded new actions to decode cleanly")
    }
  }

  @Test
  func bareCommaForSettingsFallsBackWithIssue() {
    let result = decodeBindings(
      "{\"openSettings\": [{\"keyCode\": \(kVK_ANSI_Comma), \"modifiers\": []}]}"
    )
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings[.openSettings] == KeyBindingTable.defaults[.openSettings])
      #expect(decoded.keyBindingIssues.count == 1)
      #expect(decoded.keyBindingIssues[0].action == .openSettings)
      #expect(decoded.keyBindingIssues[0].reason == .invalid)

    case .failure:
      Issue.record("expected an invalid settings key to fall back, not fail")
    }
  }

  @Test
  func bareStartFilteringNeedsNoIssue() {
    let result = decodeBindings("{\"startFiltering\": [{\"keyCode\": 3, \"modifiers\": []}]}")
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings[.startFiltering] == [ResolvedKey(keyCode: 3, modifiers: [])])
      #expect(decoded.keyBindingIssues.isEmpty)

    case .failure:
      Issue.record("expected a bare start-filtering key to decode")
    }
  }

  @Test
  func writtenNextKeepsOnlyWrittenKeys() {
    let result = decodeBindings(
      "{\"next\": [{\"keyCode\": \(kVK_DownArrow), \"modifiers\": []}]}"
    )
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings[.next]
        == [ResolvedKey(keyCode: UInt16(kVK_DownArrow), modifiers: [])])

    case .failure:
      Issue.record("expected a written next to decode")
    }
  }

  @Test
  func bareCommitDisplacesDefaultNext() {
    let result = decodeBindings(
      "{\"commit\": [{\"keyCode\": \(kVK_ANSI_J), \"modifiers\": []}]}"
    )
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings[.commit]
        == [ResolvedKey(keyCode: UInt16(kVK_ANSI_J), modifiers: [])])
      #expect(!decoded.config.keyBindings[.next].contains(
        ResolvedKey(keyCode: UInt16(kVK_ANSI_J), modifiers: [])
      ))
      #expect(decoded.keyBindingIssues.contains(where: {
        $0.action == .next && $0.reason == .conflict
          && $0.detail.contains("keyCode 38 is already taken")
      }))

    case .failure:
      Issue.record("expected a bare commit to displace the default next")
    }
  }

  @Test
  func modifierWordsAreLowercase() {
    let result = decodeBindings(
      "{\"show\": [{\"keyCode\": \(kVK_Tab), \"modifiers\": [\"CMD\"]}]}"
    )
    switch result {
    case .success(let decoded):
      #expect(decoded.config.keyBindings[.show] == KeyBindingTable.defaults[.show])
      #expect(decoded.keyBindingIssues.count == 1)

    case .failure:
      Issue.record("expected an uppercase modifier to be invalid")
    }
  }
}
