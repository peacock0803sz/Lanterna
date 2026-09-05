#ifndef LANTERNA_PRIVATE_APIS_H
#define LANTERNA_PRIVATE_APIS_H

#include <ApplicationServices/ApplicationServices.h>

/// Window-server id of the window an accessibility element stands for.
///
/// Undocumented, but exported from ApplicationServices and the only way to tie
/// an `AXUIElement` to a `CGWindowID` without Screen Recording. The project
/// constitution approves this single private function by name; it is declared
/// here because Swift has no syntax for declaring an external C symbol, and a
/// C target's `include/` directory is what SwiftPM turns into an importable
/// module.
///
/// Returns `kAXErrorSuccess` and writes a non-zero id for a real window. Any
/// other result means the element has no window-server id, which callers treat
/// as "not a window to list" rather than as an application-wide failure.
extern AXError _AXUIElementGetWindow(AXUIElementRef element, CGWindowID *outWindowID);

#endif /* LANTERNA_PRIVATE_APIS_H */
