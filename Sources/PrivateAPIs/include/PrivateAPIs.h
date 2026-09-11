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
/// one. The project's private-API policy allows this function by name, because
/// it is what lets the switcher avoid Screen Recording; anything else added to
/// this header needs the same case made for it. It is declared here because
/// Swift has no supported syntax for declaring an external C symbol, and a C
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
enum {
    kCGSHotKeyCommandTab = 1,
    kCGSHotKeyCommandShiftTab = 2,
};

/// Turns one of those shortcuts off, or back on.
///
/// Undocumented, but re-exported from CoreGraphics, so linking AppKit resolves
/// it. The private-API policy above allows it by name for the same kind of
/// reason `_AXUIElementGetWindow` is allowed: nothing public does the job.
/// While the system still holds Cmd+Tab, the Dock and the window server
/// consume the press before it reaches any application hotkey, so a switcher
/// bound to Cmd+Tab is never reached at all. The public
/// `PushSymbolicHotKeyMode` is not a substitute: it can only disable every
/// symbolic hotkey at once — Cmd+Space and the screenshot keys with it — it
/// needs accessibility access, and it undoes itself when the application is
/// deactivated, which has no meaning for a process that never becomes active.
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

#endif /* LANTERNA_PRIVATE_APIS_H */
