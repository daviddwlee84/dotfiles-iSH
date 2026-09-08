/* Ordinary, finite C/Zig ABI interoperability check; no application runtime. */
#include "abi.h"
#include <inttypes.h>
#include <stdio.h>

static int report(const char *callee, unsigned test, const struct Options *expected,
                  const struct Observed *actual) {
    int ok = actual->cols == expected->cols && actual->rows == expected->rows &&
             actual->max == expected->max;
    printf("%s case=%u %s expected=%u,%u,%zu observed=%" PRIu32 ",%" PRIu32 ",%" PRIu32 "\n",
           callee, test, ok ? "PASS" : "FAIL", expected->cols, expected->rows,
           expected->max, actual->cols, actual->rows, actual->max);
    return !ok;
}
int main(void) {
    const struct Options cases[] = {
        {2, 2, 0},
        {120, 40, 10000000},
        {17, 53, 24680},
    };
    const uint32_t tail = 0x00112233;
    int failed = 0;
    printf("layout size=%zu align=%zu offsets=%zu,%zu,%zu tail=%" PRIu32 "\n",
           sizeof(struct Options), _Alignof(struct Options),
           offsetof(struct Options, cols), offsetof(struct Options, rows),
           offsetof(struct Options, max), tail);
    for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        struct Observed actual = {0, 0, 0};
        c_by_value(&actual, cases[i], tail);
        failed += report("C-value", i, &cases[i], &actual);
        actual = (struct Observed){0, 0, 0};
        zig_by_value(&actual, cases[i], tail);
        failed += report("Zig-value", i, &cases[i], &actual);
        actual = (struct Observed){0, 0, 0};
        zig_by_pointer(&actual, &cases[i]);
        failed += report("Zig-pointer", i, &cases[i], &actual);
    }
    printf("RESULT failed=%d total=9\n", failed);
    return failed ? 1 : 0;
}
