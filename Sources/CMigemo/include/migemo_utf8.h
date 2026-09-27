// Owned by Lanterna, not upstream: the UTF-8 opening entry point
// declared beside the vendored public header.
#pragma once

#include "migemo.h"

/// Open an engine that processes text as UTF-8, with or without a
/// dictionary file. Returns NULL on failure, like `migemo_open`.
migemo *lanterna_migemo_open_utf8(const char *dict);
