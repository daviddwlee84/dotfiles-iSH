/* Link the pinned scalar i586 libghostty archive; run under an outer timeout. */
#include <stdio.h>
#include <stdlib.h>
#include <ghostty/vt.h>
int main(int argc, char **argv) {
    GhosttyTerminal terminal = NULL;
    GhosttyTerminalOptions options = {
        .cols = argc > 1 ? 120 : 2,
        .rows = argc > 1 ? 40 : 2,
        .max_scrollback = argc > 1 ? 10000000 : 0,
    };
    (void) argv;
    fprintf(stderr, "before ghostty_terminal_new cols=%u rows=%u scrollback=%zu\n",
            options.cols, options.rows, options.max_scrollback);
    fflush(stderr);
    GhosttyResult result = ghostty_terminal_new(NULL, &terminal, options);
    fprintf(stderr, "after ghostty_terminal_new result=%d nonnull=%d\n", result, terminal != NULL);
    fflush(stderr);
    if (result != GHOSTTY_SUCCESS || terminal == NULL) return 1;
    uint16_t actual_cols = 0, actual_rows = 0;
    GhosttyResult cols_result = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_COLS, &actual_cols);
    GhosttyResult rows_result = ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ROWS, &actual_rows);
    fprintf(stderr, "dimensions cols=%u rows=%u results=%d,%d\n", actual_cols, actual_rows, cols_result, rows_result);
    int correct = cols_result == GHOSTTY_SUCCESS && rows_result == GHOSTTY_SUCCESS
        && actual_cols == options.cols && actual_rows == options.rows;
    ghostty_terminal_free(terminal);
    fputs("after ghostty_terminal_free\n", stderr);
    return correct ? 0 : 2;
}
