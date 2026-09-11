/// The panel as the code deciding when to show it sees it: something that can
/// be put up with a list, taken down, and asked whether it is up.
///
/// The seam is here so that the show and hide decisions can be exercised
/// against a fake. A real panel needs a window server, which a test process
/// has no business asking for, and the transitions worth getting right — a
/// toggle and a dismissal on activation — are exactly the ones that are
/// invisible in a screenshot.
@MainActor
protocol SwitcherSurface {
    var isPresented: Bool { get }
    func present(windows: [WindowItem])
    func dismiss()
}

extension SwitcherPanel: SwitcherSurface {}
