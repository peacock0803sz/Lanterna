// Owned by Lanterna, not upstream: opens an engine that always
// processes text as UTF-8. Without a dictionary file the engine
// leaves its charset unset, so Swift sets the UTF-8 procedures here,
// next to the engine's own headers, instead of reaching past the
// public interface.
#include <stddef.h>

#include "charset.h"
#include "migemo_utf8.h"

migemo *
lanterna_migemo_open_utf8(const char *dict)
{
    migemo *mo = migemo_open(dict);
    if (mo) {
        migemo_setproc_char2int(mo, charset_utf8_char2int);
        migemo_setproc_int2char(mo, charset_utf8_int2char);
    }
    return mo;
}
