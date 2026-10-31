import Foundation

// MARK: - FastSearchModifierIssue

/// One Fast Search modifier the file held and the decoding left out.
struct FastSearchModifierIssue: Equatable, Sendable {
  /// Where the entry stood in the file's list.
  let index: Int
  /// Why it was left out, in plain words.
  let reason: String

  /// The diagnostics line, ending with where the entry stood.
  var diagnosticsLine: String {
    "fast search modifier skipped (\(reason)): fastSearchModifiers[\(index)]"
  }
}

// MARK: - AppConfiguration + Fast Search

/// The list of Fast Search modifiers. A value that is not a list refuses
/// the file like any other list key; an entry this build cannot read is
/// left out on its own, so a modifier added by a later build, or a typo,
/// costs that one key rather than the whole feature.
extension AppConfiguration {

  /// Adds the Fast Search modifiers to a decoded file.
  static func withFastSearchModifiers(
    _ dict: [String: Any],
    decoded: DecodedConfiguration
  ) -> Result<DecodedConfiguration, ConfigDecodeError> {
    guard let raw = dict["fastSearchModifiers"] else { return .success(decoded) }
    guard let entries = raw as? [Any] else {
      return .failure(.invalidValue(key: "fastSearchModifiers"))
    }
    var decoded = decoded
    var found = Set<FastSearchModifier>()
    for (index, entry) in entries.enumerated() {
      guard let spelling = entry as? String else {
        decoded.fastSearchModifierIssues.append(FastSearchModifierIssue(index: index, reason: "not a string"))
        continue
      }
      guard let modifier = FastSearchModifier(rawValue: spelling) else {
        decoded.fastSearchModifierIssues.append(
          FastSearchModifierIssue(index: index, reason: "unknown value \"\(escaped(spelling))\"")
        )
        continue
      }
      found.insert(modifier)
    }
    decoded.config.fastSearchModifiers = found.isEmpty ? nil : FastSearchModifier.allCases.filter(found.contains)
    return .success(decoded)
  }

  /// The modifier list line, in the fixed order. Absent writes nothing.
  static func fastSearchModifierEntries(_ config: ValidConfiguration) -> [String] {
    guard let modifiers = config.fastSearchModifiers, !modifiers.isEmpty else { return [] }
    let spellings = modifiers.map { "\"\($0.rawValue)\"" }
    return ["  \"fastSearchModifiers\": [" + spellings.joined(separator: ", ") + "]"]
  }

}
