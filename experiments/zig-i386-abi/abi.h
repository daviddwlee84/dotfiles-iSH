#ifndef ZIG_I386_ABI_PROBE_H
#define ZIG_I386_ABI_PROBE_H
#include <stddef.h>
#include <stdint.h>

struct Options {
    uint16_t cols;
    uint16_t rows;
    size_t max;
};
struct Observed {
    uint32_t cols;
    uint32_t rows;
    uint32_t max;
};
_Static_assert(sizeof(size_t) == 4, "This probe targets 32-bit Linux");
_Static_assert(sizeof(struct Options) == 8, "Options must occupy two i386 words");
_Static_assert(_Alignof(struct Options) == 4, "Options alignment");
_Static_assert(offsetof(struct Options, cols) == 0, "cols offset");
_Static_assert(offsetof(struct Options, rows) == 2, "rows offset");
_Static_assert(offsetof(struct Options, max) == 4, "max offset");
_Static_assert(sizeof(struct Observed) == 12, "Observed layout");

/* The destination pointer comes first. The same explicitly typed trailing
 * argument exists in BOTH languages; its initialized word bounds the observed
 * fields if aggregate lowering consumes one more word than the C ABI does.
 * No wrong-prototype aliases, casts, variadic calls, or opaque data are used. */
void c_by_value(struct Observed *out, struct Options value, uint32_t tail);
void zig_by_value(struct Observed *out, struct Options value, uint32_t tail);
void zig_by_pointer(struct Observed *out, const struct Options *value);
#endif
