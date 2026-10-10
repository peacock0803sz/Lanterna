import Foundation
@testable import Lanterna
import Testing

// MARK: - KeyBindingSchemaTests

/// The config schemas spell out the action names by hand, so a new action
/// can land in Swift without either schema learning of it. These read the
/// checked-in files and hold their action names to `KeyBindingAction`.
struct KeyBindingSchemaTests {

  // MARK: Internal

  @Test
  func jsonSchemaListsEveryAction() throws {
    let data = try Data(contentsOf: Self.configDirectory.appendingPathComponent("config-schema.json"))
    let schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let properties = try #require(schema["properties"] as? [String: Any])
    let keyBindings = try #require(properties["keybindings"] as? [String: Any])
    let actions = try #require(keyBindings["properties"] as? [String: Any])
    #expect(Set(actions.keys) == Self.actionNames)
  }

  @Test
  func pklSchemaListsEveryAction() throws {
    let source = try String(
      contentsOf: Self.configDirectory.appendingPathComponent("ConfigSchema.pkl"),
      encoding: .utf8
    )
    let body = try #require(
      source.components(separatedBy: "open class KeyBindings {").dropFirst().first?
        .components(separatedBy: "\n}").first
    )
    let names = body.split(separator: "\n").compactMap { line -> String? in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.contains(": Listing<KeyBinding>") else { return nil }
      return trimmed.components(separatedBy: ":").first
    }
    #expect(Set(names) == Self.actionNames)
  }

  // MARK: Private

  private static let actionNames = Set(KeyBindingAction.allCases.map(\.rawValue))

  /// `config/` at the repository root, found from this file's own path.
  private static var configDirectory: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("config")
  }

}
