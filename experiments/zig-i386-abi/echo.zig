const Options = extern struct {
    cols: u16,
    rows: u16,
    max: usize,
};
const Observed = extern struct {
    cols: u32,
    rows: u32,
    max: u32,
};
comptime {
    if (@sizeOf(usize) != 4 or @sizeOf(Options) != 8 or @alignOf(Options) != 4 or
        @offsetOf(Options, "cols") != 0 or @offsetOf(Options, "rows") != 2 or
        @offsetOf(Options, "max") != 4 or @sizeOf(Observed) != 12)
        @compileError("Probe requires the expected 32-bit C layouts");
}

pub export fn zig_by_value(out: *Observed, value: Options, tail: u32) callconv(.c) void {
    _ = tail;
    out.* = .{ .cols = value.cols, .rows = value.rows, .max = @intCast(value.max) };
}

pub export fn zig_by_pointer(out: *Observed, value: *const Options) callconv(.c) void {
    out.* = .{ .cols = value.cols, .rows = value.rows, .max = @intCast(value.max) };
}
