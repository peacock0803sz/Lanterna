/// How one special window kind is shown in the switcher list.
///
/// Mirrors the config file values (`"show"`, `"hide"`, `"separateAtBottom"`).
/// Absent keys mean the defaults in `DisplayModes.defaults`.
enum DisplayMode: String, Sendable {
    /// Mixed into the ordinary rows.
    case show
    /// Kept out of the list without a query. A row matching the query
    /// returns below the separator so it stays reachable.
    case hide
    /// Parked below the separator, under the kind's heading unless an
    /// earlier kind in drawing order parks the row too.
    case separateAtBottom
}

/// One row's subgroup below the separator, in drawing order.
enum DisplaySubgroup: Sendable, Hashable {
    case otherSpace
    case hiddenApp
    case minimized
    case fullscreen

    /// The subgroups in the order they draw.
    static let drawingOrder: [DisplaySubgroup] = [
        .otherSpace, .hiddenApp, .minimized, .fullscreen,
    ]
}

/// Where one row goes: the ordinary rows, out of the list, or one subgroup.
enum RowPlacement: Equatable, Sendable {
    case ordinary
    case hidden
    case separated(DisplaySubgroup)
}

/// The four display modes, and what they do to rows.
///
/// Rows carry facts (`WindowItem` flags) and this carries policy, so a row
/// never decides its own place.
struct DisplayModes: Equatable, Sendable {
    var otherSpace: DisplayMode
    var hiddenApp: DisplayMode
    var minimized: DisplayMode
    var fullscreen: DisplayMode

    /// The arrangement of record: minimized and hidden rows park below,
    /// other-Space and fullscreen rows mix in.
    static let defaults = DisplayModes(
        otherSpace: .show,
        hiddenApp: .separateAtBottom,
        minimized: .separateAtBottom,
        fullscreen: .show
    )

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
        var ordinary: [WindowItem] = []
        var grouped: [DisplaySubgroup: [WindowItem]] = [:]
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
            case let .separated(subgroup):
                grouped[subgroup, default: []].append(row)
            }
        }
        let subgroups = DisplaySubgroup.drawingOrder.compactMap { subgroup in
            grouped[subgroup].map { (subgroup, $0) }
        }
        return (ordinary, subgroups)
    }

    /// The rows in the order the panel draws them: the ordinary rows, then
    /// the subgroups in drawing order, each in the order it arrived in.
    /// Hidden rows are left out; callers narrow first.
    static func displayOrdered(
        _ rows: [WindowItem],
        modes: DisplayModes,
        queryIsEmpty: Bool,
        matches: Set<WindowItem.Identifier>
    ) -> [WindowItem] {
        let (ordinary, subgroups) = sections(
            of: rows,
            modes: modes,
            queryIsEmpty: queryIsEmpty,
            matches: matches
        )
        return ordinary + subgroups.flatMap(\.1)
    }
}
