#ifndef LANTERNA_PRIVATE_APIS_H
#define LANTERNA_PRIVATE_APIS_H

#include <ApplicationServices/ApplicationServices.h>

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

#endif /* LANTERNA_PRIVATE_APIS_H */
