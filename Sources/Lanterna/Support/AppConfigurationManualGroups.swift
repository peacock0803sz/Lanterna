import Foundation

// MARK: - GroupAssignmentIssue

/// One group assignment the file held and the decoding left out.
struct GroupAssignmentIssue: Equatable, Sendable {
  /// Where the entry stood in the file's list.
  let index: Int
  /// Why it was left out, in plain words.
  let reason: String

  /// The diagnostics line, ending with where the entry stood.
  var diagnosticsLine: String {
    "group assignment skipped (\(reason)): groupAssignments[\(index)]"
  }
}

// MARK: - RowOrderIssue

/// One row-order entry the file held and the decoding left out.
struct RowOrderIssue: Equatable, Sendable {
  /// Where the entry stood in the file's list.
  let index: Int
  /// Why it was left out, in plain words.
  let reason: String

  /// The diagnostics line, ending with where the entry stood.
  var diagnosticsLine: String {
    "row order skipped (\(reason)): rowOrder[\(index)]"
  }
}

// MARK: - AppConfiguration + row order

/// The keys for hand-arranged row orders. A value that is not a list
/// refuses the file; an entry that cannot be read, or that names a
/// group an earlier entry already named, is left out with an issue.
extension AppConfiguration {

  // MARK: Internal

  /// Adds the row orders to a decoded file.
  static func withRowOrder(
    _ dict: [String: Any],
    decoded: DecodedConfiguration
  ) -> Result<DecodedConfiguration, ConfigDecodeError> {
    guard let raw = dict["rowOrder"] else { return .success(decoded) }
    guard let entries = raw as? [Any] else {
      return .failure(.invalidValue(key: "rowOrder"))
    }
    var decoded = decoded
    var seen = Set<Int>()
    for (index, entry) in entries.enumerated() {
      switch rowOrderEntry(from: entry) {
      case .success(let order):
        guard seen.insert(order.group).inserted else {
          decoded.rowOrderIssues.append(
            RowOrderIssue(index: index, reason: "duplicate group \(order.group)")
          )
          continue
        }
        decoded.config.rowOrder.append(order)

      case .failure(let reason):
        decoded.rowOrderIssues.append(RowOrderIssue(index: index, reason: reason.text))
      }
    }
    return .success(decoded)
  }

  // MARK: Private

  /// Reads one row-order entry: a group number holding a nonempty list
  /// of row keys. Anything else leaves the entry out.
  private static func rowOrderEntry(from entry: Any) -> Result<RowOrderEntry, UnreadableAssignment> {
    guard
      let object = entry as? [String: Any],
      let rawGroup = object["group"],
      let group = jsonInt(rawGroup),
      (1 ... maximumGroupCount).contains(group),
      let rawKeys = object["keys"] as? [Any],
      !rawKeys.isEmpty
    else {
      return .failure(UnreadableAssignment(text: "unreadable entry"))
    }
    let keys = rawKeys.compactMap { $0 as? String }.filter { !$0.isEmpty }
    guard keys.count == rawKeys.count, !keys.isEmpty else {
      return .failure(UnreadableAssignment(text: "unreadable entry"))
    }
    return .success(RowOrderEntry(group: group, keys: keys))
  }

}

// MARK: - AppConfiguration + manual groups

/// The keys for manual groups. The count, the heading style and the names
/// are read like the other keys, so a bad value refuses the file; the
/// assignments are read one entry at a time, like the exclusions, so one
/// bad entry costs only itself.
extension AppConfiguration {

  // MARK: Internal

  /// The largest group count, and the largest group number.
  static let maximumGroupCount = 9

  /// Reads the count, heading style and names into the configuration.
  static func checkedManualGroups(
    _ dict: [String: Any],
    into config: inout ValidConfiguration
  ) -> Result<Void, ConfigDecodeError> {
    switch checkedOptionalInt(dict, key: "groupCount", minimum: 1) {
    case .success(let found):
      guard found.map({ $0 <= maximumGroupCount }) ?? true else {
        return .failure(.invalidValue(key: "groupCount"))
      }
      config.groupCount = found

    case .failure(let error):
      return .failure(error)
    }
    switch checkedOptionalWord(dict, key: "groupHeadingStyle", as: GroupHeadingStyle.self) {
    case .success(let found):
      config.groupHeadingStyle = found
    case .failure(let error):
      return .failure(error)
    }
    guard let rawNames = dict["groupNames"] else { return .success(()) }
    guard let names = groupNames(from: rawNames) else {
      return .failure(.invalidValue(key: "groupNames"))
    }
    config.groupNames = names
    return .success(())
  }

  /// Adds the group assignments to a decoded file. A value that is not a
  /// list refuses the file; an entry that cannot be read, or that names an
  /// application an earlier entry already named, is left out with an issue.
  static func withGroupAssignments(
    _ dict: [String: Any],
    decoded: DecodedConfiguration
  ) -> Result<DecodedConfiguration, ConfigDecodeError> {
    guard let raw = dict["groupAssignments"] else { return .success(decoded) }
    guard let entries = raw as? [Any] else {
      return .failure(.invalidValue(key: "groupAssignments"))
    }
    var decoded = decoded
    var seen = Set<String>()
    for (index, entry) in entries.enumerated() {
      switch assignment(from: entry) {
      case .success(let assignment):
        guard seen.insert(assignment.bundleID.lowercased()).inserted else {
          decoded.groupAssignmentIssues.append(
            GroupAssignmentIssue(index: index, reason: "duplicate bundleID \(assignment.bundleID)")
          )
          continue
        }
        decoded.config.groupAssignments.append(assignment)

      case .failure(let reason):
        decoded.groupAssignmentIssues.append(GroupAssignmentIssue(index: index, reason: reason.text))
      }
    }
    return .success(decoded)
  }

  /// The lines for the manual group keys, in any order: the encoder sorts
  /// every line by its key. Names and assignments past the count are
  /// written too, so raising the count brings them back.
  static func manualGroupEntries(_ config: ValidConfiguration) -> [String] {
    var entries = [String]()
    if let groupCount = config.groupCount {
      entries.append(encodedInt(key: "groupCount", value: groupCount))
    }
    if let groupHeadingStyle = config.groupHeadingStyle {
      entries.append(encodedString(key: "groupHeadingStyle", value: groupHeadingStyle.rawValue))
    }
    if !config.groupNames.isEmpty {
      let pairs = config.groupNames.sorted { $0.key < $1.key }.map { "\"\($0.key)\": \"\(escaped($0.value))\"" }
      entries.append("  \"groupNames\": { " + pairs.joined(separator: ", ") + " }")
    }
    if !config.groupAssignments.isEmpty {
      let rows = config.groupAssignments.map { entry in
        "    { \"bundleID\": \"\(escaped(entry.bundleID))\", \"group\": \(entry.group) }"
      }
      entries.append("  \"groupAssignments\": [\n" + rows.joined(separator: ",\n") + "\n  ]")
    }
    return entries
  }

  // MARK: Private

  /// Why one assignment entry could not be read.
  private struct UnreadableAssignment: Error {
    let text: String
  }

  /// The names keyed "1" to "9", or nil when any key or value is not one.
  private static func groupNames(from raw: Any) -> [Int: String]? {
    guard let object = raw as? [String: Any] else { return nil }
    var names = [Int: String]()
    for (key, value) in object {
      guard
        let number = Int(key), String(number) == key,
        (1 ... maximumGroupCount).contains(number),
        let name = value as? String
      else {
        return nil
      }
      names[number] = name
    }
    return names
  }

  private static func assignment(from entry: Any) -> Result<GroupAssignment, UnreadableAssignment> {
    guard
      let object = entry as? [String: Any],
      let bundleID = (object["bundleID"] as? String).map(GroupAssignment.trimmed),
      !bundleID.isEmpty,
      let rawGroup = object["group"], let group = jsonInt(rawGroup)
    else {
      return .failure(UnreadableAssignment(text: "unreadable entry"))
    }
    guard (1 ... maximumGroupCount).contains(group) else {
      return .failure(UnreadableAssignment(text: "group out of range \(group)"))
    }
    return .success(GroupAssignment(bundleID: bundleID, group: group))
  }

}
