// --------------------------------------------------------------------------
// The VIC-II, a frame at a time: what the C64 shows for its memory, a frame's register writes
// and the CPU's stores to the memory the VIC reads, each at the beam position it lands.
//
// Transmission64's invitation uses the VIC's ordinary modes (text, multicolour bitmap, the
// invalid ECM+BMM black, eight sprites) and changes registers between lines, never inside a
// character: part 3's NMI switching the charset every 64 lines, the IRQs turning the screen
// off and on, the border bars of the first transition. What it does do is race the beam: its
// screen updates (part 1's rings, part 2's colour cycling, part 3's panel) take most of a frame,
// so a cell shows its new value this frame only if the store landed before the VIC fetched it.
// So the model draws line by line, applying the stores timed before each line's first fetch,
// and latches a row's screen bytes and colours on its bad line, as the VIC does.
//
// Geometry (VICE 3.9 x64sc, PAL, measured on 1988's captures and these): physical row r is
// raster line r + 11, column c is sprite X c - 16, so the C64's 320x200 window (lines 51..250,
// X 24..343) is the machine's visible window and its borders are the machine's. Pixels are
// palette index 1 + C64 colour; 0 is the border, a real raster in the cart (its per-line
// colour is `border`, with a mid-line change in `split_x`/`split_c`).
// --------------------------------------------------------------------------
const line_mod = @import("vic_line.zig");
const sprite_mod = @import("vic_sprite.zig");
const store_mod = @import("vic_store.zig");
const dirty_mod = @import("vic_dirty.zig");
const border_mod = @import("vic_border.zig");
pub const splitColumn = border_mod.splitColumn;

pub const COLS = 400;
pub const ROWS = 280;
pub const FIRST_LINE = 11; // raster line of physical row 0
pub const LINES = 312; // PAL
pub const CYCLES = 63; // a PAL line
pub const FRAME = LINES * CYCLES;
pub const NREG = 0x2F;
pub const BANK: u8 = 0x38; // a write here is $DD00: the VIC bank is 3 - (value & 3)
pub const WIN_LEFT = 40; // physical column of X 24
pub const WIN_TOP = 51; // first raster line of the window
pub const WIN_LINES = 200;
// A register or memory byte written before this cycle of a line acts on the line: the VIC's
// first fetch for the window (the c-access of cell 0 on a bad line) is at cycle 15.
pub const EARLY: u8 = 15;

// align(4): 8 bytes, not 6, so a copied Write is never a 4-byte access at 2 mod 4 (one traps on the board)
pub const Write = struct { line: u16 align(4), cyc: u8, reg: u8, val: u8 };
pub const Store = store_mod.Store;
pub const Stores = store_mod.Stores;
pub const Mem = line_mod.Mem;

/// A frame's register writes, in line/cycle order.
pub const Queue = struct {
    pub const MAX = 128;
    buf: [MAX]Write = undefined,
    n: usize = 0,

    pub fn w(self: *Queue, line: u16, cyc: u8, reg: u8, val: u8) void {
        if (self.n == MAX) @panic("vic queue full"); // a part emitting more than the C64 can
        var i = self.n; // the IRQs emit in time order; a handler's tail carried in is sorted in
        while (i > 0 and later(self.buf[i - 1], line, cyc)) : (i -= 1) self.buf[i] = self.buf[i - 1];
        self.buf[i] = .{ .line = line, .cyc = cyc, .reg = reg, .val = val };
        self.n += 1;
    }

    /// A write `cyc` cycles into `line` (cycles may run past the line).
    pub fn at(self: *Queue, line: u16, cyc: u32, reg: u8, val: u8) void {
        self.w(line + @as(u16, @intCast(cyc / CYCLES)), @intCast(cyc % CYCLES), reg, val);
    }

    /// Keep the writes timed past the frame (line >= 312) for the next one, renumbered.
    pub fn carry(self: *Queue) void {
        var k: usize = 0;
        for (self.buf[0..self.n]) |wr| {
            if (wr.line < LINES) continue;
            self.buf[k] = wr;
            self.buf[k].line -= LINES;
            k += 1;
        }
        self.n = k;
    }

    pub fn items(self: *const Queue) []const Write {
        return self.buf[0..self.n];
    }
};

fn later(p: Write, line: u16, cyc: u8) bool {
    return p.line > line or (p.line == line and p.cyc > cyc);
}

pub const Out = struct {
    pub const ROWS_COLS = ROWS * COLS;
    pix: *[ROWS * COLS]u8,
    border: [ROWS]u8 = .{0} ** ROWS, // C64 border colour at the start of each row
    split_x: [ROWS]u16 = .{0} ** ROWS, // a mid-row change to split_c from this column (0 = none)
    split_c: [ROWS]u8 = .{0} ** ROWS,
    window: [ROWS]bool = .{false} ** ROWS, // the row's window holds pixels (else all border)
};

pub const Vic = struct {
    reg: [NREG]u8,
    bank: u8 = 0, // VIC bank 0..3 ($0000, $4000, $8000, $C000)
    vb: bool = true, // vertical border flip-flop (set = border)
    vm: [40]u8 = .{0} ** 40, // the video matrix line: screen bytes latched on the bad line
    cm: [40]u8 = .{0} ** 40, // and the colour nibbles
    dirty: dirty_mod.Dirty = .{}, // which window lines to draw again

    pub fn init(regs: [NREG]u8, dd00: u8) Vic {
        return .{ .reg = regs, .bank = 3 - (dd00 & 3) };
    }

    /// One PAL frame (lines 0..311) of `q`'s writes and `st`'s stores (beam time order) into
    /// `out`; the stores land in `mem`. Returns how many stores were applied: the rest are
    /// timed past the frame's end (the caller carries them to the next frame).
    pub fn frame(self: *Vic, q: *const Queue, st: []const Store, mem: Mem, out: *Out) usize {
        const ws = q.items();
        var k: usize = 0;
        var s: usize = 0;
        for (0..LINES) |l| {
            const line: u16 = @intCast(l);
            const t0: u32 = @as(u32, line) * CYCLES;
            s = store_mod.applyUntil(st, s, t0 + EARLY, mem, self.screenAt(), &self.dirty.epoch);
            const start = self.reg[0x20];
            var split: u8 = 0; // cycle of the line's first border colour change
            var after = start;
            var end = k;
            while (end < ws.len and ws[end].line == line) : (end += 1) {
                const wr = ws[end];
                if (wr.reg == 0x20 and wr.val & 15 != after & 15) {
                    if (split == 0) split = wr.cyc;
                    after = wr.val;
                } else if (wr.cyc < EARLY) self.write(wr);
            }
            self.verticalBorder(line);
            if (line >= FIRST_LINE and line < FIRST_LINE + ROWS) {
                const r = line - FIRST_LINE;
                self.drawRow(r, line, mem, out);
                border_mod.row(out, r, start, split, after);
            }
            while (k < end) : (k += 1) self.write(ws[k]);
        }
        // writes timed past line 311 stay in the queue: the caller carries them (Queue.carry)
        return store_mod.applyUntil(st, s, FRAME, mem, self.screenAt(), &self.dirty.epoch);
    }

    fn drawRow(self: *Vic, r: usize, line: u16, mem: Mem, out: *Out) void {
        const row = out.pix[r * COLS ..][0..COLS];
        // DEN cleared in the frame blanks the rest of it (VICE shows the border colour)
        const in_window = !self.vb and self.reg[0x11] & 0x10 != 0 and line >= WIN_TOP and line < WIN_TOP + WIN_LINES;
        if (!in_window) {
            if (out.window[r]) @memset(row[WIN_LEFT .. WIN_LEFT + 320], 0);
            out.window[r] = false;
            return;
        }
        const was = out.window[r];
        out.window[r] = true;
        const wl = line - WIN_TOP;
        const ctx = line_mod.Ctx{ .reg = &self.reg, .bank = self.bank, .mem = mem, .vm = &self.vm, .cm = &self.cm };
        if (wl % 8 == 0) {
            self.latch(ctx, wl / 8);
            self.dirty.latch(wl / 8, &self.vm, &self.cm);
        }
        if (!self.dirty.need(wl, &self.reg, self.bank, sprite_mod.covers(ctx, line), was)) return;
        line_mod.draw(ctx, wl, row[WIN_LEFT..][0..320]);
        sprite_mod.draw(ctx, line, row);
    }

    fn latch(self: *Vic, ctx: line_mod.Ctx, cell_row: u16) void {
        const scr = ctx.screen() + cell_row * 40;
        for (0..40) |c| {
            self.vm[c] = ctx.mem.vic(self.bank, scr + @as(u16, @intCast(c)));
            self.cm[c] = ctx.mem.col[cell_row * 40 + c];
        }
    }

    fn screenAt(self: *const Vic) u32 {
        return @as(u32, self.bank) * 0x4000 + @as(u32, self.reg[0x18] >> 4) * 0x400;
    }

    fn write(self: *Vic, wr: Write) void {
        if (wr.reg == BANK) {
            self.bank = 3 - (wr.val & 3);
        } else if (wr.reg < NREG) {
            self.reg[wr.reg] = wr.val;
        }
    }

    fn verticalBorder(self: *Vic, line: u16) void {
        const rsel = self.reg[0x11] & 0x08 != 0;
        if (line == @as(u16, if (rsel) 251 else 247)) self.vb = true;
        if (line == @as(u16, if (rsel) 51 else 55) and self.reg[0x11] & 0x10 != 0) self.vb = false;
    }
};
