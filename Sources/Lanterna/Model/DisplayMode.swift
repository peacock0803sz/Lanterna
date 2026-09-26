/// How one special window kind is shown in the switcher list.
///
/// Mirrors the config file values (`"show"`, `"hide"`, `"separateAtBottom"`).
/// Absent keys mean the defaults in `DisplayModes.defaults`.
enum DisplayMode: String, Sendable {
    /// Mixed into the ordinary rows.
    case show
    /// Kept out of the list without a query. A row matching the query
    /// returns to its subgroup so it stays reachable.
    case hide
    /// Parked below the separator in the kind's subgroup.
    case separateAtBottom
}

/// One row's subgroup below the separator, in drawing order.
enum DisplaySubgroup: Sendable {
    case otherSpace
    case hiddenApp
    case minimized
    case fullscreen
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

    /// Where one row goes. Hiding wins over parking, and a row matching the
    /// query escapes hiding into its subgroup. Ties between subgroups go to
    /// the first in drawing order. Rows with nothing known stay ordinary:
    /// missing information never hides.
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
        guard !applicable.isEmpty else { return .ordinary }
        if applicable.contains(where: { $0.0 == .hide }) {
            if !queryIsEmpty, matchesQuery {
                return .separated(firstSubgroup(of: row))
            }
            return .hidden
        }
        if applicable.contains(where: { $0.0 == .separateAtBottom }) {
            return .separated(firstSubgroup(of: row))
        }
        return .ordinary
    }

    /// The subgroup one row belongs below the separator: the first of its
    /// kinds in drawing order.
    private static func firstSubgroup(of row: WindowItem) -> DisplaySubgroup {
        if row.isOnOtherSpace {
            return .otherSpace
        }
        if row.isHidden {
            return .hiddenApp
        }
        if row.isMinimized {
            return .minimized
        }
        return .fullscreen
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

    /// The rows in the order the panel draws them: the ordinary rows, then
    /// the subgroups in drawing order, each in the order it arrived in.
    /// Hidden rows are left out; callers narrow first.
    static func displayOrdered(
        _ rows: [WindowItem],
        modes: DisplayModes,
        queryIsEmpty: Bool,
        matches: Set<WindowItem.Identifier>
    ) -> [WindowItem] {
        var ordinary: [WindowItem] = []
        var subgroups: [DisplaySubgroup: [WindowItem]] = [:]
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
                subgroups[subgroup, default: []].append(row)
            }
        }
        return ordinary
            + (subgroups[.otherSpace] ?? [])
            + (subgroups[.hiddenApp] ?? [])
            + (subgroups[.minimized] ?? [])
            + (subgroups[.fullscreen] ?? [])
    }
}
