// --------------------------------------------------------------------------
// THE LOST BOYS / TWIDDLE DEMO — the logo as comptime ink runs.
// logo.raw (158x91, index 0 = transparent, 4 = ink) holds 2,776 ink pixels in
// 730 horizontal runs. Testing all 14,378 bytes every frame cost 0.27 Mc; the
// runs paint the same pixel set (built here, from the same file) and skip the
// holes without looking at them.
// --------------------------------------------------------------------------

pub const LOGO_W = 158;
pub const LOGO_H = 91;
const logo_b = @embedFile("../../assets/screens/tlb_spoon/logo.raw");

pub const Run = struct { x: u8, len: u8 };

fn countRuns() usize {
    var n: usize = 0;
    for (0..LOGO_H) |y| {
        var prev: u8 = 0;
        for (logo_b[y * LOGO_W ..][0..LOGO_W]) |v| {
            if (v != 0 and prev == 0) n += 1;
            prev = v;
        }
    }
    return n;
}

const NRUNS = blk: {
    @setEvalBranchQuota(100_000);
    break :blk countRuns();
};

/// row_start[y] .. row_start[y + 1] index `runs` for logo row y.
pub const Table = struct {
    runs: [NRUNS]Run,
    row_start: [LOGO_H + 1]u16,
};

pub const table: Table = blk: {
    @setEvalBranchQuota(200_000);
    var t: Table = undefined;
    var n: usize = 0;
    for (0..LOGO_H) |y| {
        t.row_start[y] = n;
        const row = logo_b[y * LOGO_W ..][0..LOGO_W];
        var x: usize = 0;
        while (x < LOGO_W) {
            if (row[x] == 0) {
                x += 1;
                continue;
            }
            const x0 = x;
            while (x < LOGO_W and row[x] != 0) x += 1;
            t.runs[n] = .{ .x = x0, .len = x - x0 };
            n += 1;
        }
    }
    t.row_start[LOGO_H] = n;
    break :blk t;
};

comptime {
    if (logo_b.len != LOGO_W * LOGO_H) @compileError("logo.raw is not 158x91");
}
