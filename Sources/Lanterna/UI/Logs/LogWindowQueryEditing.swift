import Foundation

// MARK: - Log Window Query Editing

extension LogWindowState {

  func addQueryToken(_ token: String) {
    guard query.mode == .lightweight else { return }
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var tokens = splitLogQueryTokens(query.lightweightText)
    if tokens.contains(trimmed) {
      return
    }
    tokens.append(trimmed)
    query.lightweightText = tokens.joined(separator: " ")
    refresh()
  }

  func replaceQueryKeys(_ keys: [String], with token: String?) {
    guard query.mode == .lightweight else { return }
    let lowered = Set(keys.map { $0.lowercased() })
    var tokens = splitLogQueryTokens(query.lightweightText).filter { entry in
      guard let key = logQueryKey(of: entry)?.lowercased() else { return true }
      return !lowered.contains(key)
    }
    if let token {
      let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        tokens.append(trimmed)
      }
    }
    query.lightweightText = tokens.joined(separator: " ")
    refresh()
  }

  func setLevelFilter(_ token: String?) {
    replaceQueryKeys(["level"], with: token)
  }

  func setCategoryFilter(_ token: String?) {
    replaceQueryKeys(["category", "cat"], with: token)
  }

  func setLaunchFilter(_ token: String?) {
    replaceQueryKeys(["launch"], with: token)
  }

  func removeChip(_ chip: String) {
    guard query.mode == .lightweight else { return }
    if chip == "__time__" {
      resetTime()
      return
    }
    let parsed = LightweightFilter.parse(query.lightweightText)
    query.lightweightText = parsed.removingChip(chip)
    refresh()
  }

  func clearQuery() {
    guard query.mode == .lightweight else { return }
    query.lightweightText = ""
    resetTime()
  }

}
