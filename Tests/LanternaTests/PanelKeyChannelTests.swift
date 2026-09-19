import AppKit
import Carbon.HIToolbox
@testable import Lanterna
import Testing

/// A press as the keyboard would make it, with nothing held and no repeat.
private func aPress(_ keyCode: Int, _ modifiers: NSEvent.ModifierFlags = []) -> PanelKeystroke {
    PanelKeystroke(keyCode: UInt16(keyCode), modifiers: modifiers, isARepeat: false)
}

/// Stands in for AppKit's two monitor calls, so what the real channel does with
/// them can be watched without a keyboard and without a window server.
///
/// Records the calls in order rather than counting each kind. The counts alone
/// cannot tell a start that took the previous monitor off first from one that
/// took it off afterwards, and the second of those is the state the real
/// channel's own comment is written against: two monitors over one keyboard,
/// asking the same question twice and acting on both answers. Order is the
/// claim, so order is what is kept.
@MainActor
private final class MonitorSpy {
    enum Call: Equatable {
        case install
        case remove
    }

    private(set) var calls: [Call] = []

    /// Whether an install hands a token back. False is AppKit declining, which
    /// it is documented to do and which there is no way to provoke from the
    /// real call — and it is the one case the answer from `start` exists for.
    var installSucceeds = true

    /// A channel wired to this spy and to nothing else.
    func makeChannel() -> LocalKeyEventChannel {
        LocalKeyEventChannel(
            installMonitor: { [self] _, _ in
                calls.append(.install)
                return installSucceeds ? Token() : nil
            },
            removeMonitor: { [self] _ in calls.append(.remove) }
        )
    }

    /// What AppKit would hand back: something opaque whose only use is being
    /// handed in again. A class, so that two installs produce two of them, as
    /// two real monitors would.
    private final class Token {}
}

/// A handler that swallows everything, for the cases that are about the
/// monitor rather than about what a press means.
@MainActor
private func swallowing(_: PanelKeystroke) -> PanelKeyDisposition {
    .absorbed
}

/// The keyboard reaching the presenter, driven from the end a real monitor
/// would deliver from.
@MainActor
struct PanelKeyChannelTests {
    /// Wires a channel to a presenter the way the launch does, and hands back
    /// both ends.
    private func wired(_ fixture: Fixture) -> FakeKeyChannel {
        let channel = FakeKeyChannel()
        // Thrown away on purpose: this stand-in always installs, and the cases
        // below are about what arrives afterwards rather than about whether
        // anything was installed. The two that are about that ask the real
        // channel, which is the only one that can answer no.
        _ = channel.start(handler: fixture.presenter.handleKeyStroke)
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

    /// The answer means presses will arrive, so a monitor AppKit handed over
    /// has to produce a yes.
    @Test func aMonitorThatWentUpAnswersYes() {
        let spy = MonitorSpy()
        let channel = spy.makeChannel()

        #expect(channel.start(handler: swallowing))
        #expect(spy.calls == [.install])
    }

    /// AppKit is documented to hand nothing back, and this answer is the only
    /// notice of it anywhere in the process. Everything downstream carries on
    /// as though the keyboard were being read: the panel appears, the
    /// presenter holds an opinion about every key, and the keys themselves go
    /// to whatever is in front of the panel.
    @Test func aMonitorAppKitRefusedAnswersNo() {
        let spy = MonitorSpy()
        spy.installSucceeds = false
        let channel = spy.makeChannel()

        #expect(channel.start(handler: swallowing) == false)
        #expect(spy.calls == [.install])
    }

    /// The second start takes the first monitor off before it installs
    /// anything, and the order is the claim rather than the counts: two
    /// monitors over one keyboard would put the same press to the presenter
    /// twice and act on both answers, and a removal that arrived after the
    /// second install would leave exactly one monitor while removing the one
    /// that was meant to stay.
    @Test func startingTwiceTakesTheFirstMonitorOffFirst() {
        let spy = MonitorSpy()
        let channel = spy.makeChannel()

        _ = channel.start(handler: swallowing)
        _ = channel.start(handler: swallowing)

        #expect(spy.calls == [.install, .remove, .install])
    }

    /// Stopping takes the monitor off once, and stopping again asks for
    /// nothing. The token has already gone back to AppKit by then, and handing
    /// it the same one twice is asking it to take off a monitor it no longer
    /// knows anything about.
    @Test func stoppingTwiceAsksForOneRemoval() {
        let spy = MonitorSpy()
        let channel = spy.makeChannel()
        _ = channel.start(handler: swallowing)

        channel.stop()
        channel.stop()

        #expect(spy.calls == [.install, .remove])
    }

    /// The stand-in replaces the way the real channel does, taking whatever
    /// was listening off before it installs anything. A double looser than the
    /// thing it stands in for is a double that lets a test pass where the real
    /// one would fail, which is the whole of what a double is for.
    ///
    /// `isDelivering` afterwards is what pins the order down. A stand-in that
    /// stopped after installing would leave these same two counts and nothing
    /// listening at all.
    @Test func theStandInAlsoReplacesByRemovingFirst() {
        let fixture = Fixture()
        let channel = FakeKeyChannel()

        _ = channel.start(handler: fixture.presenter.handleKeyStroke)
        _ = channel.start(handler: fixture.presenter.handleKeyStroke)

        #expect(channel.startCount == 2)
        #expect(channel.stopCount == 2)
        #expect(channel.isDelivering)
    }
}
