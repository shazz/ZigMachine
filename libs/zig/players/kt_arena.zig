// --------------------------------------------------------------------------
// The .kt player's memory: a bump arena over a span of song RAM (past the file
// image, below the Paula rings), for what a song needs that upstream mallocs:
// its patterns, sequences, instruments, wavetable samples and FX delay lines.
// A load or a start that does not fit is refused (error.TooLarge), never
// written past the span. Pure: no chip (the native tests give it a buffer).
// --------------------------------------------------------------------------

pub const Error = error{TooLarge};

pub const Arena = struct {
    base: [*]u8 = undefined,
    len: usize = 0,
    used: usize = 0,

    pub fn init(mem: []u8) Arena {
        return .{ .base = mem.ptr, .len = mem.len, .used = 0 };
    }

    /// `n` items of T, aligned for T, zero-filled (upstream's calloc).
    pub fn alloc(self: *Arena, comptime T: type, n: usize) Error![]T {
        const a = @alignOf(T);
        const start = (@intFromPtr(self.base) + self.used + a - 1) & ~@as(usize, a - 1);
        const off = start - @intFromPtr(self.base);
        const size = n * @sizeOf(T);
        if (off > self.len or size > self.len - off) return error.TooLarge;
        self.used = off + size;
        const bytes = self.base[off..][0..size];
        @memset(bytes, 0);
        return @as([*]T, @ptrCast(@alignCast(bytes.ptr)))[0..n];
    }

    /// Back to `mark` (a value of `used`): what was allocated after it is free again.
    pub fn reset(self: *Arena, mark: usize) void {
        self.used = mark;
    }
};
