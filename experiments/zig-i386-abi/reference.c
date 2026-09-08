#include "abi.h"

void c_by_value(struct Observed *out, struct Options value, uint32_t tail) {
    (void)tail;
    out->cols = value.cols;
    out->rows = value.rows;
    out->max = value.max;
}
