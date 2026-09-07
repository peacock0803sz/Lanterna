import ApplicationServices
@testable import Lanterna
import Testing

/// The whole rule table, because this is where a window the user can see gets
/// dropped or a panel they cannot switch to gets listed.
struct WindowKindTests {
    /// The Finder desktop is reported among Finder's windows as a scroll area.
    @Test(arguments: [kAXStandardWindowSubrole, kAXDialogSubrole, kAXFloatingWindowSubrole, nil])
    func anElementThatIsNotAWindowIsNeverListed(subrole: String?) {
        #expect(WindowKind.classify(role: kAXScrollAreaRole, subrole: subrole) == nil)
    }

    @Test func aStandardWindowIsListed() {
        #expect(WindowKind.classify(role: kAXWindowRole, subrole: kAXStandardWindowSubrole) == .standard)
    }

    @Test(arguments: [kAXDialogSubrole, kAXSystemDialogSubrole])
    func aDialogIsListed(subrole: String) {
        #expect(WindowKind.classify(role: kAXWindowRole, subrole: subrole) == .dialog)
    }

    /// Font panels and inspectors are windows, but not ones a switcher offers.
    @Test(arguments: [kAXFloatingWindowSubrole, kAXSystemFloatingWindowSubrole])
    func anAuxiliaryPanelIsNotListed(subrole: String) {
        #expect(WindowKind.classify(role: kAXWindowRole, subrole: subrole) == nil)
    }

    /// Fail open: an unrecognised window still reaches the list, because
    /// hiding a window the user can see is the worse mistake.
    @Test(arguments: [kAXUnknownSubrole, "AXSomethingNewInTheNextRelease", nil])
    func anUnrecognisedSubroleIsStillListed(subrole: String?) {
        #expect(WindowKind.classify(role: kAXWindowRole, subrole: subrole) == .undetermined)
    }

    /// An unreadable role is an absent answer, not evidence against a window.
    @Test func anUnreadableRoleDoesNotExcludeOnItsOwn() {
        #expect(WindowKind.classify(role: nil, subrole: kAXStandardWindowSubrole) == .standard)
        #expect(WindowKind.classify(role: nil, subrole: nil) == .undetermined)
        #expect(WindowKind.classify(role: nil, subrole: kAXFloatingWindowSubrole) == nil)
    }
}
