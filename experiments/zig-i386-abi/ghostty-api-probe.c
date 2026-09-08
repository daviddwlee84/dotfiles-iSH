/*
 * Finite conformance checks for the real libghostty-vt public C ABI.
 *
 * Compile this translation unit with Clang, using the unmodified public
 * Ghostty headers. In particular, do not redeclare the five aggregate-taking
 * functions, cast their function pointers, or call private pointer wrappers.
 * Optional argv[1] selects one suite so a runner can bound each subprocess.
 */
#include <ghostty/vt.h>

#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static unsigned checks;
static unsigned failures;

static bool check(const char *name, bool passed) {
    ++checks;
    if (!passed) ++failures;
    printf("%s %u - %s\n", passed ? "ok" : "not ok", checks, name);
    fflush(stdout);
    return passed;
}

static bool result(const char *name, GhosttyResult actual) {
    if (actual != GHOSTTY_SUCCESS)
        printf("# %s returned %d\n", name, (int)actual);
    return check(name, actual == GHOSTTY_SUCCESS);
}

static bool equal_bytes(const char *name, const uint8_t *actual,
                        size_t actual_len, const char *expected) {
    const size_t expected_len = strlen(expected);
    bool same = actual_len == expected_len &&
                memcmp(actual, expected, expected_len) == 0;
    if (!same)
        printf("# %s: actual length %zu; expected %zu\n",
               name, actual_len, expected_len);
    return check(name, same);
}

static GhosttyTerminal terminal(uint16_t cols, uint16_t rows,
                                size_t max_scrollback) {
    GhosttyTerminal t = NULL;
    GhosttyTerminalOptions options = {
        .cols = cols, .rows = rows, .max_scrollback = max_scrollback,
    };
    if (!result("terminal_new", ghostty_terminal_new(NULL, &t, options)))
        return NULL;
    if (!check("terminal handle returned", t != NULL)) return NULL;
    uint16_t actual_cols = 0, actual_rows = 0;
    bool got_cols = result("terminal_get cols", ghostty_terminal_get(
        t, GHOSTTY_TERMINAL_DATA_COLS, &actual_cols));
    bool got_rows = result("terminal_get rows", ghostty_terminal_get(
        t, GHOSTTY_TERMINAL_DATA_ROWS, &actual_rows));
    check("options cols and rows preserved",
          got_cols && got_rows && actual_cols == cols && actual_rows == rows);
    return t;
}

static void write_text(GhosttyTerminal t, const char *text) {
    ghostty_terminal_vt_write(t, (const uint8_t *)text, strlen(text));
}

static bool scrollbar(GhosttyTerminal t, GhosttyTerminalScrollbar *bar) {
    memset(bar, 0, sizeof(*bar));
    return result("terminal_get scrollbar", ghostty_terminal_get(
        t, GHOSTTY_TERMINAL_DATA_SCROLLBAR, bar));
}

static GhosttyPoint point(GhosttyPointTag tag, uint16_t x, uint32_t y) {
    GhosttyPoint p = {0};
    p.tag = tag;
    p.value.coordinate.x = x;
    p.value.coordinate.y = y;
    return p;
}

static void cell(GhosttyTerminal t, const char *name,
                 GhosttyPointTag tag, uint16_t x, uint32_t y,
                 uint32_t expected) {
    GhosttyGridRef ref = GHOSTTY_INIT_SIZED(GhosttyGridRef);
    if (!result("terminal_grid_ref", ghostty_terminal_grid_ref(
                    t, point(tag, x, y), &ref))) return;
    uint32_t codepoints[4] = {0};
    size_t length = 0;
    bool got = result("grid_ref_graphemes", ghostty_grid_ref_graphemes(
        &ref, codepoints, 4, &length));
    if (length != 1 || codepoints[0] != expected)
        printf("# %s: length %zu, first U+%04" PRIX32 ", expected U+%04"
               PRIX32 "\n", name, length, codepoints[0], expected);
    check(name, got && length == 1 && codepoints[0] == expected);
}

static void small_terminal(void) {
    GhosttyTerminal t = terminal(2, 2, 0);
    if (t == NULL) return;
    write_text(t, "A\r\nB\r\nC\r\nD\r\nE\r\nF\r\nG\r\nH");
    GhosttyTerminalScrollbar bar;
    if (scrollbar(t, &bar))
        check("zero scrollback discards history",
              bar.total == 2 && bar.offset == 0 && bar.len == 2);
    cell(t, "2x2 first active row is G", GHOSTTY_POINT_TAG_ACTIVE, 0, 0, 'G');
    cell(t, "2x2 second active row is H", GHOSTTY_POINT_TAG_ACTIVE, 0, 1, 'H');
    ghostty_terminal_free(t);
}

static void large_terminal(void) {
    GhosttyTerminal t = terminal(120, 40, 10000000);
    if (t == NULL) return;
    for (unsigned i = 0; i < 50; ++i) {
        char text[16];
        (void)snprintf(text, sizeof(text), "%02u%s", i, i == 49 ? "" : "\r\n");
        write_text(t, text);
    }
    GhosttyTerminalScrollbar bar;
    if (scrollbar(t, &bar))
        check("10M scrollback option retains ten history rows",
              bar.total == 50 && bar.offset == 10 && bar.len == 40);
    cell(t, "120x40 active first row is 10", GHOSTTY_POINT_TAG_ACTIVE, 0, 0, '1');
    cell(t, "120x40 active last row is 49", GHOSTTY_POINT_TAG_ACTIVE, 1, 39, '9');
    cell(t, "120x40 history retains row 09", GHOSTTY_POINT_TAG_HISTORY, 1, 9, '9');
    ghostty_terminal_free(t);
}

static void grid(void) {
    GhosttyTerminal t = terminal(8, 3, 10000000);
    if (t == NULL) return;
    write_text(t, "abcdefgh\r\nijklmnop\r\nqrstuvwx");
    cell(t, "point active x0 y0", GHOSTTY_POINT_TAG_ACTIVE, 0, 0, 'a');
    cell(t, "point active x5 y1", GHOSTTY_POINT_TAG_ACTIVE, 5, 1, 'n');
    cell(t, "point active x7 y2", GHOSTTY_POINT_TAG_ACTIVE, 7, 2, 'x');
    GhosttyGridRef ref = GHOSTTY_INIT_SIZED(GhosttyGridRef);
    check("point column outside terminal is rejected",
          ghostty_terminal_grid_ref(t, point(GHOSTTY_POINT_TAG_ACTIVE, 8, 0),
                                    &ref) == GHOSTTY_INVALID_VALUE);
    check("point row outside active area is rejected",
          ghostty_terminal_grid_ref(t, point(GHOSTTY_POINT_TAG_ACTIVE, 0, 3),
                                    &ref) == GHOSTTY_INVALID_VALUE);
    ghostty_terminal_free(t);
}

static void scroll(GhosttyTerminal t, GhosttyTerminalScrollViewportTag tag,
                   intptr_t value) {
    GhosttyTerminalScrollViewport behavior = {0};
    behavior.tag = tag;
    if (tag == GHOSTTY_SCROLL_VIEWPORT_DELTA)
        behavior.value.delta = value;
    else if (tag == GHOSTTY_SCROLL_VIEWPORT_ROW)
        behavior.value.row = (size_t)value;
    ghostty_terminal_scroll_viewport(t, behavior);
}

static void viewport(void) {
    GhosttyTerminal t = terminal(8, 3, 10000000);
    if (t == NULL) return;
    write_text(t, "A0\r\nB1\r\nC2\r\nD3\r\nE4\r\nF5\r\nG6\r\nH7");
    GhosttyTerminalScrollbar bar;
    if (scrollbar(t, &bar))
        check("initial viewport at bottom", bar.total == 8 &&
              bar.offset == 5 && bar.len == 3);
    scroll(t, GHOSTTY_SCROLL_VIEWPORT_TOP, 0);
    if (scrollbar(t, &bar)) check("TOP offset is zero", bar.offset == 0);
    cell(t, "viewport at top", GHOSTTY_POINT_TAG_VIEWPORT, 1, 1, '1');
    cell(t, "history coordinate differs from active", GHOSTTY_POINT_TAG_HISTORY,
         1, 3, '3');
    cell(t, "screen includes history and active", GHOSTTY_POINT_TAG_SCREEN,
         0, 7, 'H');
    scroll(t, GHOSTTY_SCROLL_VIEWPORT_DELTA, 2);
    if (scrollbar(t, &bar)) check("positive DELTA adds two", bar.offset == 2);
    cell(t, "viewport after positive delta", GHOSTTY_POINT_TAG_VIEWPORT, 0, 1, 'D');
    scroll(t, GHOSTTY_SCROLL_VIEWPORT_DELTA, -1);
    if (scrollbar(t, &bar)) check("negative DELTA subtracts one", bar.offset == 1);
    scroll(t, GHOSTTY_SCROLL_VIEWPORT_ROW, 4);
    if (scrollbar(t, &bar)) check("ROW selects absolute four", bar.offset == 4);
    cell(t, "viewport after absolute row", GHOSTTY_POINT_TAG_VIEWPORT, 0, 0, 'E');
    scroll(t, GHOSTTY_SCROLL_VIEWPORT_ROW, 100);
    if (scrollbar(t, &bar)) check("ROW clamps at active area", bar.offset == 5);
    scroll(t, GHOSTTY_SCROLL_VIEWPORT_TOP, 0);
    scroll(t, GHOSTTY_SCROLL_VIEWPORT_BOTTOM, 0);
    if (scrollbar(t, &bar)) check("BOTTOM restores five", bar.offset == 5);
    ghostty_terminal_free(t);
}

static GhosttyFormatterTerminalOptions format_options(void) {
    GhosttyFormatterTerminalOptions options =
        GHOSTTY_INIT_SIZED(GhosttyFormatterTerminalOptions);
    options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN;
    options.trim = true;
    options.extra.size = sizeof(options.extra);
    options.extra.screen.size = sizeof(options.extra.screen);
    return options;
}

static bool format(GhosttyTerminal t, GhosttyFormatterTerminalOptions options,
                   uint8_t *output, size_t capacity, size_t *written) {
    GhosttyFormatter f = NULL;
    *written = 0;
    if (!result("formatter_terminal_new", ghostty_formatter_terminal_new(
                    NULL, &f, t, options))) return false;
    if (!check("formatter handle returned", f != NULL)) return false;
    bool success = result("formatter_format_buf", ghostty_formatter_format_buf(
        f, output, capacity, written));
    ghostty_formatter_free(f);
    return success;
}

static void formatter(void) {
    uint8_t output[16384] = {0};
    size_t written = 0;
    GhosttyFormatterTerminalOptions options = format_options();
    GhosttyTerminal t = terminal(12, 3, 0);
    if (t == NULL) return;
    write_text(t, "alpha  \r\nbeta ");
    if (format(t, options, output, sizeof(output), &written))
        equal_bytes("formatter trim enabled", output, written, "alpha\nbeta");
    options.trim = false;
    if (format(t, options, output, sizeof(output), &written))
        equal_bytes("formatter trim disabled", output, written, "alpha  \nbeta ");
    GhosttySelection selection = GHOSTTY_INIT_SIZED(GhosttySelection);
    selection.start.size = sizeof(selection.start);
    selection.end.size = sizeof(selection.end);
    bool start = result("selection start grid_ref", ghostty_terminal_grid_ref(
        t, point(GHOSTTY_POINT_TAG_ACTIVE, 1, 0), &selection.start));
    bool end = result("selection end grid_ref", ghostty_terminal_grid_ref(
        t, point(GHOSTTY_POINT_TAG_ACTIVE, 3, 0), &selection.end));
    if (start && end) {
        options.trim = true;
        options.selection = &selection;
        if (format(t, options, output, sizeof(output), &written))
            equal_bytes("formatter selection pointer", output, written, "lph");
    }
    ghostty_terminal_free(t);

    t = terminal(5, 3, 0);
    if (t == NULL) return;
    write_text(t, "1234567");
    options = format_options();
    if (format(t, options, output, sizeof(output), &written))
        equal_bytes("formatter unwrap disabled", output, written, "12345\n67");
    options.unwrap = true;
    if (format(t, options, output, sizeof(output), &written))
        equal_bytes("formatter unwrap enabled", output, written, "1234567");

    write_text(t, "\x1b[3;4H");
    options.emit = GHOSTTY_FORMATTER_FORMAT_VT;
    options.extra.screen.cursor = true;
    if (format(t, options, output, sizeof(output), &written)) {
        GhosttyTerminal copy = terminal(5, 3, 0);
        if (copy != NULL) {
            ghostty_terminal_vt_write(copy, output, written);
            uint16_t x = 0, y = 0;
            bool got_x = result("formatted cursor x", ghostty_terminal_get(
                copy, GHOSTTY_TERMINAL_DATA_CURSOR_X, &x));
            bool got_y = result("formatted cursor y", ghostty_terminal_get(
                copy, GHOSTTY_TERMINAL_DATA_CURSOR_Y, &y));
            check("nested formatter extra.screen.cursor preserves 4,3",
                  got_x && got_y && x == 3 && y == 2);
            ghostty_terminal_free(copy);
        }
    }
    ghostty_terminal_free(t);
}

static void mouse(void) {
    GhosttyMouseEvent event = NULL;
    if (!result("mouse_event_new", ghostty_mouse_event_new(NULL, &event))) return;
    if (!check("mouse event handle returned", event != NULL)) return;
    const GhosttyMousePosition positions[] = {
        {.x = 13.25f, .y = 27.5f},
        {.x = -3.75f, .y = 4096.125f},
        {.x = 0.0f, .y = 0.0f},
    };
    const char *names[] = {
        "mouse position distinct positive coordinates",
        "mouse position negative and large coordinates",
        "mouse position reset to zero",
    };
    for (size_t i = 0; i < sizeof(positions) / sizeof(positions[0]); ++i) {
        ghostty_mouse_event_set_position(event, positions[i]);
        GhosttyMousePosition actual = ghostty_mouse_event_get_position(event);
        check(names[i], actual.x == positions[i].x && actual.y == positions[i].y);
    }
    ghostty_mouse_event_free(event);
}

int main(int argc, char **argv) {
    const struct { const char *name; void (*run)(void); } suites[] = {
        {"terminal-small", small_terminal}, {"terminal-large", large_terminal},
        {"grid", grid}, {"viewport", viewport},
        {"formatter", formatter}, {"mouse", mouse},
    };
    if (argc > 2) return 2;
    unsigned selected = 0;
    for (size_t i = 0; i < sizeof(suites) / sizeof(suites[0]); ++i) {
        if (argc == 2 && strcmp(argv[1], suites[i].name) != 0) continue;
        ++selected;
        printf("# suite %s\n", suites[i].name);
        fflush(stdout);
        suites[i].run();
    }
    if (selected == 0) return 2;
    printf("1..%u\n# passed %u/%u, suites %u\n",
           checks, checks - failures, checks, selected);
    return failures == 0 ? 0 : 1;
}
