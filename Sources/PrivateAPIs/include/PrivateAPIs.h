#ifndef LANTERNA_PRIVATE_APIS_H
#define LANTERNA_PRIVATE_APIS_H

#include <ApplicationServices/ApplicationServices.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

/// Window-server id of the window an accessibility element stands for.
///
/// Undocumented, but exported from ApplicationServices and the only direct way
/// to tie an `AXUIElement` to a `CGWindowID` without Screen Recording; matching
/// frames and owners against `CGWindowListCopyWindowInfo` would be the indirect
/// one. That is the test a symbol has to pass to be declared in this header:
/// no public API does the job without a cost this app will not pay — here an
/// extra permission or matching by heuristics — argued by name for the symbol
/// rather than for private APIs as a class. It is declared here because Swift
/// has no supported syntax for declaring an external C symbol, and a C
/// target's `include/` directory is what SwiftPM turns into an importable
/// module.
///
/// Every real window seen so far returned `kAXErrorSuccess` and a non-zero id.
/// The one failure observed is `kAXErrorIllegalArgument`, for an element that
/// is not a window (the Finder desktop). The Swift caller treats
/// `kAXErrorCannotComplete` as being about the application — a timeout or an
/// unreachable peer — and every other failure as "no id"; see
/// `AXApplicationWindowReader.windowID(of:within:)`.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *outWindowID);

/// One of the window server's built-in keyboard shortcuts.
typedef int CGSSymbolicHotKey;

/// The two the switcher takes over. They are independent: disabling only
/// `kCGSHotKeyCommandTab` would leave the system's reverse switcher alive on
/// Shift+Cmd+Tab. Cmd+` (id 6, cycling one application's windows) is left to
/// the system, so no constant is given for it.
///
/// The filter invocation takes over Spotlight's. The id below is a candidate
/// verified by observation rather than a documented value: disabling it must
/// silence Spotlight, and restoring it must bring Spotlight back. It passes
/// the same test as the two above — no public API takes a system-held
/// combination over — argued here rather than for private APIs as a class.
enum {
    kCGSHotKeyCommandTab = 1,
    kCGSHotKeyCommandShiftTab = 2,
    kCGSHotKeySpotlight = 64,
};

/// Turns one of those shortcuts off, or back on.
///
/// Undocumented, but re-exported from CoreGraphics, so linking AppKit resolves
/// it. It passes the same test as `_AXUIElementGetWindow`. While the system
/// still holds Cmd+Tab, the Dock and the window server consume the press
/// before it reaches any application hotkey, so a switcher bound to Cmd+Tab is
/// never reached at all. The public `PushSymbolicHotKeyMode` is not a
/// substitute: it can only disable every symbolic hotkey at once — Cmd+Space
/// and the screenshot keys with it — it needs accessibility access, and it
/// undoes itself when the application is deactivated, which has no meaning for
/// a process that never becomes active.
///
/// Only the setter is declared. `CGSIsSymbolicHotKeyEnabled` is deliberately
/// left out, because restoring writes `true` unconditionally instead of
/// reading the current value: a run that was killed leaves the shortcut off,
/// and a later run that read that state back would take it for the user's own
/// setting and never turn it on again.
///
/// The change outlives the process, so a run that exits without restoring
/// leaves the user without their Cmd+Tab.
extern CGError CGSSetSymbolicHotKeyEnabled(CGSSymbolicHotKey hotKey, bool isEnabled);

/// This process's connection to the window server, which the Space queries
/// below take as their first argument.
typedef int CGSConnectionID;

/// The window server's id for one Space. Unique across displays.
typedef uint64_t CGSSpaceID;

/// Which of a window's Spaces `CGSCopySpacesForWindows` answers with. Only
/// "all" is declared: asked for current Spaces only, a window on another
/// Space would presumably answer with an empty list, which is also what an
/// unknown window answers, so "elsewhere" could not be told from "no answer".
enum {
    kCGSSpaceMaskAll = 0x7,
};

/// Returns the calling process's window-server connection.
///
/// Undocumented, but re-exported from CoreGraphics like the setter above.
/// Declared for the two queries below, whose case is made there.
extern CGSConnectionID CGSMainConnectionID(void);

/// Every display, each as a dictionary. The key read here is
/// "Current Space", a dictionary whose "id64" is the id of the Space that
/// display is showing. With "Displays have separate Spaces" turned off,
/// every display collapses into one entry.
///
/// Undocumented, re-exported from CoreGraphics. It passes the same test as
/// `_AXUIElementGetWindow`: no public API says which Space a display is
/// showing. `NSWorkspace` only announces that the active Space changed.
///
/// Returns a new reference. The caller treats NULL as no answer.
extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID connection) CF_RETURNS_RETAINED;

/// The Spaces the given windows are on, as `CGSSpaceID` numbers.
///
/// `windowIDs` is an array of `CGWindowID` numbers. The answer is one flat
/// list for the whole array, with no way to tell which window a Space came
/// from, so a caller that needs a per-window answer passes one window at a
/// time. A window on every Space answers with more than one id; a window the
/// server has no record of answers with an empty list, the same as a window
/// on no Space at all. So does an inactive tab of a native tab group, which
/// therefore reads as in view wherever its group is.
///
/// Undocumented, re-exported from CoreGraphics, and passes the same test:
/// no public API places a window on a Space.
///
/// Returns a new reference. The caller treats NULL as no answer.
extern CFArrayRef CGSCopySpacesForWindows(
    CGSConnectionID connection,
    int mask,
    CFArrayRef windowIDs
) CF_RETURNS_RETAINED;

#endif /* LANTERNA_PRIVATE_APIS_H */
