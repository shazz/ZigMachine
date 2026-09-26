// --------------------------------------------------------------------------
// JOUST's machine state: exactly the original's memory, so every transcribed
// routine uses the 68000's own offsets (the reference model's state.py).
//
//   mem     the relocated TEXT+BSS image, TEXT offsets 0..$1BB58, loaded at
//           BASE = $10000 as the model loads it. Code bytes matter: the RNG
//           walks them, and relocated longs in them hold BASE+x.
//   scr     the 32000-byte ST screen at SCREEN = $F8000, with the RAM just
//           below it: the wrapped right half of a sprite on the top lines
//           writes there (the model's `a_outside`), and a later erase ANDs it.
//   regs    d0-d7/a0-a7: a call may use a register the previous one left.
//
// Every value is an i64, the reference model's unbounded Python int: the
// transcriptions mask where the model masks, and nowhere else.
// --------------------------------------------------------------------------
const std = @import("std");
const pacing = @import("pacing.zig");
const sound = @import("sound.zig");
const m68k = @import("m68k.zig");
pub const V = @import("vars.zig");

pub const BASE: i64 = 0x10000;
pub const SCREEN: i64 = 0xF8000;
pub const TEXT_LEN: usize = 0x13E58;
pub const BSS_LEN: usize = 0x7D00;
pub const MEM_LEN: usize = TEXT_LEN + BSS_LEN;
pub const SLOTS: i64 = 0x0FA4;
pub const SLOT_SZ: i64 = 0x4E;
pub const NSLOTS: i64 = 14;
pub const P1: i64 = 0x0FA4;
pub const P2: i64 = 0x0FF2;
/// RAM kept below the screen (the model keeps it in a sparse dict).
pub const BELOW: usize = 0x800;
pub const M32: i64 = 0xFFFFFFFF;
pub const M16: i64 = 0xFFFF;

const PRG = @embedFile("../../assets/screens/joust/JOUST.PRG");
pub const MUR = @embedFile("../../assets/screens/joust/JOUST.MUR");
pub const HIGH_SCO = @embedFile("../../assets/screens/joust/HIGH.SCO");

/// Module scope: 146 KB that do not belong in the cart's Demo struct.
pub var mem: [MEM_LEN]u8 = undefined;
pub var scr: [BELOW + 32000]u8 = undefined;

pub const Exit = enum { none, jmp18, restart, quit };

pub const St = struct {
    regs: [16]i64,
    /// Dosound: script pointer (TEXT offset or 0), delay, temp, and the PSG.
    snd_ptr: i64,
    snd_delay: i64,
    snd_temp: i64,
    psg: [16]u8,
    /// The 16 colour registers, and a Setpalette waiting for the next VBL.
    pal: [16]u16,
    pending_pal: [16]u16,
    pal_pending: bool,
    /// The call's pure CPU cycles (set by the call), and how many it already
    /// fed to the pacer through clock().
    cycles: i64,
    clocked: i64,
    pacer: pacing.Pacer,
    exit: Exit,
    /// SFX scripts started by play_sfx since the host last collected them.
    sfx_log: [16]u8,
    sfx_n: u8,
    /// Accesses outside the program, the screen and the RAM below it: the
    /// model would have raised. Counted, and checked 0 by the harness.
    oob: u32,
    /// The TOS keyboard buffer (the iorec): characters with their scancodes.
    keybuf: [32]u32,
    key_head: u8,
    key_n: u8,

    pub fn init(self: *St) void {
        @memset(&self.regs, 0);
        self.snd_ptr = 0;
        self.snd_delay = 0;
        self.snd_temp = 0;
        @memset(&self.psg, 0);
        self.psg[7] = 0xFF;
        @memset(&self.pal, 0);
        @memset(&self.pending_pal, 0);
        self.pal_pending = false;
        self.cycles = 0;
        self.clocked = 0;
        self.pacer.init(0, pacing.VBL_CYC, pacing.TIMERC_CYC, 0, 0);
        self.exit = .none;
        self.sfx_n = 0;
        self.oob = 0;
        self.key_head = 0;
        self.key_n = 0;
        loadImage();
    }

    // ---- TEXT-offset access (unsigned) ----
    pub fn get(self: *St, off: i64, n: u8) i64 {
        return self.rd(BASE + off, n);
    }
    pub fn put(self: *St, off: i64, n: u8, v: i64) void {
        self.wr(BASE + off, n, v);
    }
    pub fn rb(self: *St, off: i64) i64 {
        return self.get(off, 1);
    }
    pub fn rw(self: *St, off: i64) i64 {
        return self.get(off, 2);
    }
    pub fn rl(self: *St, off: i64) i64 {
        return self.get(off, 4);
    }
    pub fn wb(self: *St, off: i64, v: i64) void {
        self.put(off, 1, v);
    }
    pub fn ww(self: *St, off: i64, v: i64) void {
        self.put(off, 2, v);
    }
    pub fn wl(self: *St, off: i64, v: i64) void {
        self.put(off, 4, v);
    }

    /// A named variable (vars.zig), unsigned.
    pub fn g(self: *St, v: V.Var) i64 {
        return self.get(v.off, v.n);
    }
    pub fn s(self: *St, v: V.Var, x: i64) void {
        self.put(v.off, v.n, x);
    }

    // ---- absolute-address access, as the 68000 sees it ----
    fn where(self: *St, a: i64, n: u8) ?[]u8 {
        const x = a & 0xFFFFFF;
        const len: i64 = n;
        if (x >= BASE and x + len <= BASE + @as(i64, MEM_LEN)) {
            const o: usize = @intCast(x - BASE);
            return mem[o .. o + n];
        }
        const lo = SCREEN - @as(i64, BELOW);
        if (x >= lo and x + len <= SCREEN + 32000) {
            const o: usize = @intCast(x - lo);
            return scr[o .. o + n];
        }
        self.oob += 1;
        return null;
    }

    pub fn rd(self: *St, a: i64, n: u8) i64 {
        const b = self.where(a, n) orelse return 0;
        var v: i64 = 0;
        for (b) |c| v = (v << 8) | c;
        return v;
    }

    pub fn wr(self: *St, a: i64, n: u8, v: i64) void {
        const b = self.where(a, n) orelse return;
        var x: u64 = @bitCast(v);
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            b[i] = @truncate(x);
            x >>= 8;
        }
    }

    // ---- the CPU clock ----
    /// Advance the CPU clock by n pure cycles NOW: interrupts that fall due are
    /// serviced, the Dosound tick included. Before anything that talks to the
    /// sound chip.
    pub fn clock(self: *St, n: i64) void {
        self.clocked += n;
        self.pacer.run(self, n);
    }

    // ---- registers ----
    pub fn set_d(self: *St, i: usize, v: i64, n: u8) void {
        const m: i64 = if (n == 4) M32 else if (n == 2) M16 else 0xFF;
        self.regs[i] = (self.regs[i] & ~m & M32) | (v & m);
    }
    pub fn set_a(self: *St, i: usize, v: i64) void {
        self.regs[8 + i] = v & M32;
    }

    // ---- the TOS keyboard buffer ----
    pub fn keyPush(self: *St, code: u32) void {
        if (self.key_n == self.keybuf.len) return; // the iorec is full: TOS drops it
        self.keybuf[(self.key_head + self.key_n) % self.keybuf.len] = code;
        self.key_n += 1;
    }
    pub fn keyPop(self: *St) ?u32 {
        if (self.key_n == 0) return null;
        const c = self.keybuf[self.key_head];
        self.key_head = @intCast((self.key_head + 1) % self.keybuf.len);
        self.key_n -= 1;
        return c;
    }

    /// play_sfx's note for the host: the SNDH subtune to start.
    /// Only the 17 real scripts (0..15 and the siren) are logged: anything else
    /// would be a subtune joust_sfx.sndh does not have (and a negative n would
    /// reach an unchecked cast).
    pub fn logSfx(self: *St, n: i64) void {
        if (n < 0 or n > sound.SIREN) return;
        if (self.sfx_n < self.sfx_log.len) {
            self.sfx_log[self.sfx_n] = @intCast(n);
            self.sfx_n += 1;
        }
    }

    pub fn dosoundTick(self: *St) void {
        sound.dosound_tick(self);
    }

    /// The pacer's VBL: a Setpalette waiting since the last one is installed.
    pub fn onVbl(self: *St) void {
        if (self.pal_pending) {
            self.pal = self.pending_pal;
            self.pal_pending = false;
        }
    }
};

fn be32(b: []const u8, o: usize) u32 {
    return std.mem.readInt(u32, b[o..][0..4], .big);
}

/// JOUST.PRG's TEXT relocated at BASE (GEMDOS: first long offset, then byte
/// deltas, 1 = +254), the BSS cleared, and JOUST.MUR in the BSS where the
/// start-up loads it.
fn loadImage() void {
    const tlen = be32(PRG, 2);
    const dlen = be32(PRG, 6);
    const slen = be32(PRG, 14);
    @memcpy(mem[0 .. tlen + dlen], PRG[0x1C .. 0x1C + tlen + dlen]);
    @memset(mem[tlen + dlen ..], 0);
    var p: usize = 0x1C + tlen + dlen + slen;
    var off: usize = be32(PRG, p);
    p += 4;
    while (off != 0) {
        const v = std.mem.readInt(u32, mem[off..][0..4], .big) +% @as(u32, @intCast(BASE));
        std.mem.writeInt(u32, mem[off..][0..4], v, .big);
        while (true) {
            const b = PRG[p];
            p += 1;
            if (b == 0) {
                off = 0;
                break;
            }
            if (b == 1) {
                off += 254;
                continue;
            }
            off += b;
            break;
        }
    }
    @memcpy(mem[TEXT_LEN .. TEXT_LEN + 32000], MUR);
    // A reset (the harness's, or a second power-on in one instance) must not
    // inherit the last run's screen or the RAM below it: the model starts both
    // empty.
    @memset(&scr, 0);
}

// ---- 68000 arithmetic (m68k.zig), re-exported ----
pub const s8 = m68k.s8;
pub const s16 = m68k.s16;
pub const s32 = m68k.s32;
pub const setw = m68k.setw;
pub const setb = m68k.setb;
pub const swap = m68k.swap;
pub const divu = m68k.divu;
pub const rorl = m68k.rorl;
pub const lsrl = m68k.lsrl;
pub const shr = m68k.shr;
pub const bit = m68k.bit;
