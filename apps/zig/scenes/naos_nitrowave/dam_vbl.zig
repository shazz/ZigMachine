// --------------------------------------------------------------------------
// F3's VBL ($7A000), generated like the other two from a template ($3B812) and
// a fragment stream ($3C89C..$409C0). Its logical program, in order
// (prototypes/naos_nitrowave_re/dam_fold.txt, irregular.py):
//   logo    36 lines: per line two longs of the distortion table (a4): the
//           screen offset and the logo source; 11 groups of planes 1..3, the
//           first and last cleared, nine from the logo (54 bytes a line).
//           a4, the logo offset and the screen line are kept ($361F8..$36200)
//   band    the landscape's planes 0/1: 62 lines through the routine pair at
//           $30F6C/$30F70 (a5, a6 from the main loop), then 28 lines through
//           $30FE8/$30FEC (from $3102C, $31028). Each routine is straight-line
//           code -- move.l (a6)[+],d(a5), lea d(a6), lea $E6(a5) -- run here
//           as the data it is
//   logo    the next 16 lines, from where the first part stopped
//   scroll  nine characters of 3 groups x 16 lines (planes 0..2) at *$30C92
//   clear   4 lines x 26 groups (planes 0..2) at *$30C9C
// The colour-register writes between them are in dam_show.zig.
// --------------------------------------------------------------------------
const st = @import("st.zig");

pub const LINE: u32 = 230;
const LOGO_SRC_LINE: u32 = 54;

/// The registers the main loop hands the VBL.
pub const Regs = struct { a4: u32, a5: u32, a6: u32 };

pub fn run(r: *const st.Ram, regs: *Regs) void {
    const scr = r.l(0x361F4);
    var a4 = regs.a4;
    for (0..36) |i| {
        const ii: u32 = @intCast(i);
        logoLine(r, r.l(a4) +% scr +% LINE * ii, r.l(a4 + 4) +% LOGO_SRC_LINE * ii);
        a4 += 8;
    }
    r.sl(0x361F8, a4);
    r.sl(0x361FC, LOGO_SRC_LINE * 36);
    r.sl(0x36200, scr + LINE * 36);
    band(r, regs, 0x30F6C, 62);
    regs.a6 = r.l(0x31028);
    regs.a5 = r.l(0x3102C);
    band(r, regs, 0x30FE8, 28);
    logoRest(r);
    scroller(r);
    clear(r);
}

/// The 16 logo lines after the bands, from the kept a4 / offsets.
fn logoRest(r: *const st.Ram) void {
    var a4 = r.l(0x361F8);
    var d7 = r.l(0x36200);
    var d6 = r.l(0x361FC);
    for (0..16) |_| {
        logoLine(r, r.l(a4) +% d7, r.l(a4 + 4) +% d6);
        a4 += 8;
        d7 += LINE;
        d6 += LOGO_SRC_LINE;
    }
}

fn logoLine(r: *const st.Ram, dst: u32, src: u32) void {
    @memset(r.bytes(dst + 2, 6), 0);
    for (1..10) |g| {
        const gg: u32 = @intCast(g);
        r.cp(dst + 8 * gg + 2, src + 6 * (gg - 1), 6);
    }
    @memset(r.bytes(dst + 80 + 2, 6), 0);
}

fn band(r: *const st.Ram, regs: *Regs, pair: u32, lines: usize) void {
    for (0..lines) |_| {
        routine(r, regs, r.l(pair));
        routine(r, regs, r.l(pair + 4));
    }
}

/// One band routine, instruction by instruction: it is only ever these.
fn routine(r: *const st.Ram, regs: *Regs, at: u32) void {
    var pc = at;
    var guard: usize = 0;
    while (guard < 64) : (guard += 1) {
        const op = r.w(pc);
        const d: u32 = @bitCast(@as(i32, @as(i16, @bitCast(r.w(pc + 2)))));
        switch (op) {
            0x4E75 => return, // rts
            0x4E71 => pc += 2, // nop
            0x2B5E, 0x2B56 => { // move.l (a6)+ / (a6), d(a5)
                r.sl(regs.a5 +% d, r.l(regs.a6));
                if (op == 0x2B5E) regs.a6 += 4;
                pc += 4;
            },
            0x4DEE => { // lea d(a6), a6
                regs.a6 +%= d;
                pc += 4;
            },
            0x4BED => { // lea d(a5), a5
                regs.a5 +%= d;
                pc += 4;
            },
            else => return, // never met: the routines hold nothing else
        }
    }
}

fn scroller(r: *const st.Ram) void {
    var a4 = r.l(0x30C92);
    for (0..9) |c| {
        var src = r.l(0x30C6E + 4 * @as(u32, @intCast(c)));
        for (0..16) |row| {
            for (0..3) |g| {
                r.cp(a4 + LINE * @as(u32, @intCast(row)) + 8 * @as(u32, @intCast(g)), src, 6);
                src += 6;
            }
        }
        a4 += 0x18;
    }
}

/// 26 groups a line (lea $18 every 26th group: the next line).
fn clear(r: *const st.Ram) void {
    const a4 = r.l(0x30C9C);
    for (0..4) |line| {
        for (0..26) |g| @memset(r.bytes(a4 + LINE * @as(u32, @intCast(line)) + 8 * @as(u32, @intCast(g)), 6), 0);
    }
}
