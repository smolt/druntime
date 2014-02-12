/**
 * Shims for libunwind macros on ARM.
 *
 * It would be possible to reimplement those entirely in D, but to avoid
 * an unmaintainable amount of dependencies on internal implementation details,
 * we use the C versions instead.
 *
 * Copyright: David Nadlinger, 2012.
 * License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors:   David Nadlinger
 */
// dano - TODO: find how to do this
typedef unsigned long _Unwind_Word;

#ifdef __arm__

#include <unwind.h>

_Unwind_Word _d_eh_GetIP(struct _Unwind_Context *context)
{
    //return _Unwind_GetIP(context);
    return 0;
}

void _d_eh_SetIP(struct _Unwind_Context *context, _Unwind_Word new_value)
{
    //_Unwind_SetIP(context, new_value);
}

void _d_eh_SetGR(struct _Unwind_Context *context, int index, _Unwind_Word new_value)
{
    //_Unwind_SetGR(context, index, new_value);
}

#endif
