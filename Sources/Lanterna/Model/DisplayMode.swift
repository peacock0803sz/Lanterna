// MARK: - DisplayMode

/// How one special window kind is shown in the switcher list.
///
/// Mirrors the config file values (`"show"`, `"hide"`, `"separateAtBottom"`).
/// Absent keys mean the defaults in `DisplayModes.defaults`.
enum DisplayMode: String, Sendable {
  /// Mixed into the ordinary rows.
  case show
  /// Kept out of the list without a query. A row the query matches comes
  /// back under the heading of the first of its kinds that hides it, so
  /// it stays reachable.
  case hide
  /// Parked below the ordinary rows, under the heading of the first of
  /// the row's kinds that parks it. A row that another of its kinds
  /// hides is not parked.
  case separateAtBottom
}

// MARK: - DisplaySubgroup

/// One row's subgroup below the separator, in drawing order.
enum DisplaySubgroup: Sendable, Hashable {
  case otherSpace
  case hiddenApp
  case minimized
  case fullscreen

  /// The subgroups in the order they draw.
  static let drawingOrder: [DisplaySubgroup] = [
    .otherSpace,
    .hiddenApp,
    .minimized,
    .fullscreen,
  ]
}

// MARK: - RowPlacement

/// Where one row goes: the ordinary rows, out of the list, or one subgroup.
enum RowPlacement: Equatable, Sendable {
  case ordinary
  case hidden
  case separated(DisplaySubgroup)
}

// MARK: - DisplayModes

/// One display mode for each special kind, and what they do to rows.
///
/// Rows carry facts (`WindowItem` flags) and this carries policy, so a row
/// never decides its own place.
struct DisplayModes: Equatable, Sendable {

  // MARK: Internal

  /// The modes for keys the config file leaves out: minimized and hidden
  /// rows park below, other-Space and fullscreen rows mix in.
  static let defaults = DisplayModes(
    otherSpace: .show,
    hiddenApp: .separateAtBottom,
    minimized: .separateAtBottom,
    fullscreen: .show
  )

  var otherSpace: DisplayMode
  var hiddenApp: DisplayMode
  var minimized: DisplayMode
  var fullscreen: DisplayMode

  /// Where one row goes. Hiding wins over parking. A row matching the
  /// query escapes hiding into the subgroup of the first of its kinds, in
  /// drawing order, whose mode hides it; a parked row goes to the first
  /// of its kinds whose mode parks it, so a kind shown in the list never
  /// files a row under its heading. Rows with nothing known stay
  /// ordinary: missing information never hides.
  static func placement(
    of row: WindowItem,
    modes: DisplayModes,
    queryIsEmpty: Bool,
    matchesQuery: Bool
  ) -> RowPlacement {
    let applicable: [(DisplayMode, DisplaySubgroup)] = [
      (row.isOnOtherSpace ? modes.otherSpace : nil, .otherSpace),
      (row.isHidden ? modes.hiddenApp : nil, .hiddenApp),
      (row.isMinimized ? modes.minimized : nil, .minimized),
      (row.isFullscreen ? modes.fullscreen : nil, .fullscreen),
    ].compactMap { mode, subgroup in mode.map { ($0, subgroup) } }
    if let hiding = applicable.first(where: { $0.0 == .hide }) {
      return !queryIsEmpty && matchesQuery ? .separated(hiding.1) : .hidden
    }
    if let parking = applicable.first(where: { $0.0 == .separateAtBottom }) {
      return .separated(parking.1)
    }
    return .ordinary
  }

  /// The effective modes for one run: present keys win, absent keys mean
  /// the defaults.
  static func effective(from config: ValidConfiguration) -> DisplayModes {
    DisplayModes(
      otherSpace: config.otherSpaceMode ?? defaults.otherSpace,
      hiddenApp: config.hiddenAppMode ?? defaults.hiddenApp,
      minimized: config.minimizedMode ?? defaults.minimized,
      fullscreen: config.fullscreenMode ?? defaults.fullscreen
    )
  }

  /// The rows split for drawing: the ordinary rows, then each non-empty
  /// subgroup in drawing order, each in the order it arrived in.
  static func sections(
    of rows: [WindowItem],
    modes: DisplayModes,
    queryIsEmpty: Bool,
    matches: Set<WindowItem.Identifier>
  ) -> (ordinary: [WindowItem], subgroups: [(DisplaySubgroup, [WindowItem])]) {
    var ordinary = [WindowItem]()
    var grouped = [DisplaySubgroup: [WindowItem]]()
    for row in rows {
      switch placement(
        of: row,
        modes: modes,
        queryIsEmpty: queryIsEmpty,
        matchesQuery: matches.contains(row.id)
      ) {
      case .ordinary:
        ordinary.append(row)
      case .hidden:
        continue
      case .separated(let subgroup):
        grouped[subgroup, default: []].append(row)
      }
    }
    let subgroups = DisplaySubgroup.drawingOrder.compactMap { subgroup in
      grouped[subgroup].map { (subgroup, $0) }
    }
    return (ordinary, subgroups)
  }

  /// The rows the panel draws for a query, split as above: the rows the
  /// query matches, less the ones the modes keep out. The filter, the
  /// view and the height all ask this, so what is kept out is decided
  /// one way wherever it is asked. Exclusions run first: an excluded row
  /// reaches neither the narrowing nor the modes.
  static func sections(
    of rows: [WindowItem],
    modes: DisplayModes,
    query: String,
    exclusions: [ExclusionRule] = [],
    fuzzy: Bool = false,
    ordering: SearchOrdering = .mru
  ) -> (ordinary: [WindowItem], subgroups: [(DisplaySubgroup, [WindowItem])]) {
    let listed = WindowExclusion.excluding(rows, rules: exclusions)
    let matched: [WindowItem] =
      if RomajiMatcher.engine.isOpen {
        WindowFilter.matching(query, against: listed, engine: RomajiMatcher.engine)
      } else if fuzzy {
        WindowFilter.matching(query, against: listed, fuzzy: true)
      } else {
        WindowFilter.matching(query, against: listed)
      }
    let (ordinary, subgroups) = sections(
      of: matched,
      modes: modes,
      queryIsEmpty: query.isEmpty,
      matches: Set(matched.map(\.id))
    )
    guard ordering == .score, !query.isEmpty else {
      return (ordinary, subgroups)
    }
    return (
      ordinary: scoreRanked(ordinary, query: query),
      subgroups: subgroups.map { ($0.0, scoreRanked($0.1, query: query)) }
    )
  }

  /// The rows the panel shows for a query, in the order it draws them: the
  /// ordinary rows, then the subgroups in drawing order, each in the order
  /// it arrived in. The filter hands this order to the choice and to the
  /// panel, so the arrows step through the rows as they are drawn.
  static func displayOrdered(
    _ rows: [WindowItem],
    modes: DisplayModes,
    query: String,
    exclusions: [ExclusionRule] = [],
    fuzzy: Bool = false,
    ordering: SearchOrdering = .mru
  ) -> [WindowItem] {
    let (ordinary, subgroups) = sections(
      of: rows,
      modes: modes,
      query: query,
      exclusions: exclusions,
      fuzzy: fuzzy,
      ordering: ordering
    )
    return ordinary + subgroups.flatMap(\.1)
  }

  // MARK: Private

  /// One section ranked best-match-first: contiguous substring matches,
  /// then earlier match starts, with ties in the order they arrived in.
  /// Ranking stays inside the section, so parking and hiding policies
  /// stand however the rows order. A romaji match counts as contiguous,
  /// ranked by where its span starts.
  private static func scoreRanked(_ rows: [WindowItem], query: String) -> [WindowItem] {
    guard RomajiMatcher.engine.isOpen else {
      return WindowFilter.scoreOrdered(rows, query: query)
    }
    return rows.enumerated().map { entry in
      (offset: entry.offset, start: engineMatchStart(of: entry.element, query: query), row: entry.element)
    }.sorted {
      if $0.start != $1.start {
        return $0.start < $1.start
      }
      return $0.offset < $1.offset
    }.map(\.row)
  }

  /// Where the romaji match starts, or last when the row never matched
  /// through the engine.
  private static func engineMatchStart(of row: WindowItem, query: String) -> Int {
    let text = WindowFilter.combinedText(of: row)
    guard let first = WindowFilter.matchedRanges(query: query, in: text, engine: RomajiMatcher.engine).first else {
      return Int.max
    }
    return text.distance(from: text.startIndex, to: first.lowerBound)
  }

}
