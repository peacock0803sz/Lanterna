import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// A press as the keyboard would make it, with nothing held and no repeat.
private func aPress(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: modifiers, isARepeat: false)
}

/// The keyboard reaching the presenter, driven from the end a real monitor
/// would deliver from.
@MainActor
struct PanelKeyChannelTests {
    /// Wires a channel to a presenter the way the launch does, and hands back
    /// both ends.
    private func wired(_ fixture: Fixture) -> FakeKeyChannel {
        let channel = FakeKeyChannel()
        channel.start(handler: fixture.presenter.handleKeyStroke)
        return channel
    }

    /// The monitor runs for the whole of the process's life, so it sees every
    /// press the user makes, most of them while no panel is anywhere. Those
    /// have to carry on to whatever they were for.
    @Test func aPressWithNoPanelUpCarriesOn() {
        let fixture = Fixture()
        let channel = wired(fixture)

        #expect(channel.send(aPress(kVK_ANSI_A)) == .passedThrough)
        #expect(channel.send(aPress(kVK_Return)) == .passedThrough)
        #expect(fixture.log.lines.isEmpty)
        #expect(fixture.surface.isPresented == false)
    }

    /// A panel that is up holds the whole keyboard, including the keys it has
    /// no use for. Handing one of those back would send it down the responder
    /// chain, where a press nothing handles rings the system alert; a
    /// character key handed back would type into whatever is in front of the
    /// panel.
    @Test func everyKeyIsSwallowedWhileThePanelIsUp() {
        let fixture = Fixture()
        let channel = wired(fixture)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        #expect(channel.send(aPress(kVK_ANSI_A)) == .absorbed)
        #expect(channel.send(aPress(kVK_ANSI_Q, .command)) == .absorbed)
        #expect(channel.send(aPress(kVK_F1)) == .absorbed)
    }

    /// Swallowing is not acting. A key with no meaning here must leave the
    /// panel exactly as it found it, and say nothing into the log: the lines
    /// are counted, and one per keystroke would drown the ones that matter.
    @Test func aSwallowedKeyDoesNothingElse() {
        let fixture = Fixture()
        let channel = wired(fixture)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)
        let linesAfterThePanelWentUp = fixture.log.lines

        for _ in 0 ..< 20 {
            channel.send(aPress(kVK_ANSI_A))
        }

        #expect(fixture.surface.isPresented)
        #expect(fixture.surface.dismissCount == 0)
        #expect(fixture.surface.presentedLists.count == 1)
        #expect(fixture.log.lines == linesAfterThePanelWentUp)
    }

    /// A monitor that has been taken off delivers nothing at all, which is a
    /// different thing from delivering a press and swallowing it.
    @Test func aStoppedChannelDeliversNothing() {
        let fixture = Fixture()
        let channel = wired(fixture)
        fixture.presenter.handleHotkey(.forward, deliveryDelay: nil)

        channel.stop()

        #expect(channel.isDelivering == false)
        #expect(channel.send(aPress(kVK_ANSI_A)) == nil)
    }
}
