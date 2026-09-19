/// The panel as the code deciding when to show it sees it: something that can
/// be put up with a list, taken down, and asked whether it is up.
///
/// It is behind a protocol because a real panel needs a window server, which
/// a test process has no business asking for. Whether it is up is asked of the
/// panel rather than tracked alongside it: two records of one thing are two
/// things that can disagree.
///
/// Kept in a file of its own rather than beside the presenter that uses it.
/// This is the boundary the step that lets the selection move widens — keys,
/// a chosen row, and the panel being asked to redraw one — and a boundary
/// that grows belongs somewhere its growth is not charged to a file that is
/// already close to the length the linter allows.
@MainActor
protocol SwitcherSurface {
    var isPresented: Bool { get }
    func present(windows: [WindowItem])
    func dismiss()
}

extension SwitcherPanel: SwitcherSurface {}
