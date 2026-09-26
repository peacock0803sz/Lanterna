import CoreGraphics
import Foundation
import PrivateAPIs

/// Says which windows sit on a Space that no display is showing.
///
/// The enumerator asks once per pass, after the accessibility reading and
/// on the same thread, with every window id that reading produced.
protocol SpaceLocating: Sendable {
    /// The ids among `windowIDs` known to be on another Space. A window the
    /// answer says nothing about is left out: unknown never hides.
    func windowsOnOtherSpaces(among windowIDs: [CGWindowID]) -> Set<CGWindowID>
    /// The ids among `windowIDs` known to sit only on fullscreen Spaces.
    /// Default empty so fakes naming only other-Space windows keep working.
    func fullscreenWindows(among windowIDs: [CGWindowID]) -> Set<CGWindowID>
}

extension SpaceLocating {
    func fullscreenWindows(among _: [CGWindowID]) -> Set<CGWindowID> {
        []
    }
}

/// The decision itself, apart from the window server that feeds it.
enum SpacePlacement {
    /// Whether a window is on another Space: it is on at least one Space, and
    /// none of them is being shown by any display. A window on every Space
    /// lists its display's shown Space among its Spaces, so it reads as in
    /// view. An empty list is no answer, and no known current Space means
    /// nothing can be compared; both read false.
    static func isOnOtherSpace(
        windowSpaces: [CGSSpaceID],
        currentSpaces: Set<CGSSpaceID>
    ) -> Bool {
        guard !windowSpaces.isEmpty, !currentSpaces.isEmpty else {
            return false
        }
        return currentSpaces.isDisjoint(with: windowSpaces)
    }

    /// Whether a window is natively fullscreen: it is on at least one Space,
    /// and every Space it is on is a fullscreen Space. An empty answer or no
    /// known fullscreen Space reads false.
    static func isFullscreen(
        windowSpaces: [CGSSpaceID],
        fullscreenSpaces: Set<CGSSpaceID>
    ) -> Bool {
        guard !windowSpaces.isEmpty, !fullscreenSpaces.isEmpty else {
            return false
        }
        return Set(windowSpaces).isSubset(of: fullscreenSpaces)
    }

    /// The fullscreen Spaces, read from the per-display Space lists
    /// `CGSCopyManagedDisplaySpaces` answers with. Type 4 is fullscreen.
    static func fullscreenSpaces(from displays: [[String: Any]]) -> Set<CGSSpaceID> {
        Set(displays.flatMap { display in
            ((display["Spaces"] as? [[String: Any]]) ?? []).compactMap { space in
                guard (space["type"] as? NSNumber)?.intValue == 4 else { return nil }
                return (space["id64"] as? NSNumber)?.uint64Value
            }
        })
    }

    /// The Space each display is showing, read from the per-display
    /// dictionaries `CGSCopyManagedDisplaySpaces` answers with. A display
    /// whose entry lacks a readable current Space adds nothing.
    static func currentSpaces(from displays: [[String: Any]]) -> Set<CGSSpaceID> {
        Set(displays.compactMap { display in
            let current = display["Current Space"] as? [String: Any]
            return (current?["id64"] as? NSNumber)?.uint64Value
        })
    }
}

/// Asks the window server.
///
/// One call for the displays' current Spaces, then one per window, because
/// `CGSCopySpacesForWindows` answers a batch with a single list that does
/// not say which window each Space belongs to. Each call goes to the window
/// server alone, with no application in the way, so a wedged application
/// cannot hold one up the way it holds up an accessibility message.
struct WindowServerSpaceLocator: SpaceLocating {
    func windowsOnOtherSpaces(among windowIDs: [CGWindowID]) -> Set<CGWindowID> {
        guard !windowIDs.isEmpty else {
            return []
        }
        let connection = CGSMainConnectionID()
        let displays: CFArray? = CGSCopyManagedDisplaySpaces(connection)
        let currentSpaces = SpacePlacement.currentSpaces(
            from: displays as? [[String: Any]] ?? []
        )
        // Without a current Space every answer would read false anyway.
        guard !currentSpaces.isEmpty else {
            return []
        }
        return Set(windowIDs.filter { windowID in
            SpacePlacement.isOnOtherSpace(
                windowSpaces: Self.spaces(of: windowID, connection: connection),
                currentSpaces: currentSpaces
            )
        })
    }

    func fullscreenWindows(among windowIDs: [CGWindowID]) -> Set<CGWindowID> {
        guard !windowIDs.isEmpty else {
            return []
        }
        let connection = CGSMainConnectionID()
        let displays: CFArray? = CGSCopyManagedDisplaySpaces(connection)
        let fullscreenSpaces = SpacePlacement.fullscreenSpaces(
            from: displays as? [[String: Any]] ?? []
        )
        guard !fullscreenSpaces.isEmpty else {
            return []
        }
        return Set(windowIDs.filter { windowID in
            SpacePlacement.isFullscreen(
                windowSpaces: Self.spaces(of: windowID, connection: connection),
                fullscreenSpaces: fullscreenSpaces
            )
        })
    }

    private static func spaces(of windowID: CGWindowID, connection: CGSConnectionID) -> [CGSSpaceID] {
        let windowIDs = [NSNumber(value: windowID)] as CFArray
        let answer: CFArray? = CGSCopySpacesForWindows(connection, Int32(kCGSSpaceMaskAll), windowIDs)
        let spaces = answer as? [NSNumber] ?? []
        return spaces.map(\.uint64Value)
    }
}
