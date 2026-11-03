// --------------------------------------------------------------------------
// A switch built in slices. On the board one frame doing the whole switch (ZX0
// depack, palette decode, VRAM table, plane pixels, caption) cost 9-53 Mc: 7-43
// missed VBLs. Here the next picture/mode is built one slice a frame while the
// current one shows, into what nothing shows: the depack buffer (with copper lists
// nothing reads it after a switch), the spare palette table (cop.zig) and the
// spare pixel buffers (flip.zig). The switch frame then only flips the plane
// bases and rewrites the lists (mpp_truecolor.zig `show`).
//
// `step(1)` is one slice (~0.1-0.2 Mc); `step(FINISH)` runs the job to the end
// in one call: a key press, init, and a machine with one buffer do that.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const blob = @import("blob.zig");
const cop = @import("cop.zig");
const flip = @import("flip.zig");
const gallery = @import("gallery.zig");

const W = blob.W;
const H = blob.H;
pub const IMAGE_H: usize = 180; // rows 180..199 are the caption band (converter's IMAGE_H)
pub const INK: u8 = 1; // caption palette: 0 black, 1 white
pub const FINISH: u32 = std.math.maxInt(u32);
const TABLE_ROWS: usize = 32; // 1 KB CHISEL rows a slice
const PIXEL_ROWS: usize = 25; // plane rows a slice

pub const Progress = blob.Progress;

pub const Job = struct {
    picture: u8,
    mode: u8,
    decoder: blob.Decoder,
    pass: enum { decode, table, pixels, caption, done, failed } = .decode,
    row: usize = 0,

    /// Build `picture` in `mode` into `work` and the hidden VRAM; null when the blob is
    /// unreadable (the caller says so).
    pub fn init(picture: u8, mode: u8, work: []align(4) u8) ?Job {
        const d = blob.Decoder.init(gallery.PACKED[picture][mode], gallery.MODES[mode].kind, work) orelse return null;
        return .{ .picture = picture, .mode = mode, .decoder = d };
    }

    pub fn view(self: *const Job) blob.View {
        return self.decoder.view;
    }

    pub fn kind(self: *const Job) blob.Kind {
        return gallery.MODES[self.mode].kind;
    }

    /// One slice (`units` = 1) or, with FINISH, all of it. The table pass runs only with lists.
    pub fn step(self: *Job, os: *zg.ZigOS, units: u32, lists: bool) Progress {
        switch (self.pass) {
            .decode => switch (self.decoder.step(units)) {
                .more => {},
                .failed => self.pass = .failed,
                .done => self.pass = if (lists and self.kind() == .indexed) .table else .pixels,
            },
            .table => {
                const pal = self.view().pal;
                self.row = cop.copyRows(pal, self.row, TABLE_ROWS *| @as(usize, units));
                if (self.row >= cop.tableRows(pal)) self.next(.pixels);
            },
            .pixels => {
                const end = @min(H, self.row +| PIXEL_ROWS *| @as(usize, units));
                if (self.kind() == .indexed) copyRows(os, self.view().idx, self.row, end) else copyTcRows(os, self.view().idx, self.row, end);
                self.row = end;
                if (end == H) self.next(.caption);
            },
            .caption => {
                self.caption(os);
                self.pass = .done;
            },
            .done => return .done,
            .failed => return .failed,
        }
        return switch (self.pass) {
            .done => .done,
            .failed => .failed,
            else => .more,
        };
    }

    pub fn finish(self: *Job, os: *zg.ZigOS, lists: bool) Progress {
        while (true) switch (self.step(os, FINISH, lists)) {
            .more => {},
            else => |p| return p,
        };
    }

    fn next(self: *Job, pass: @TypeOf(self.pass)) void {
        self.pass = pass;
        self.row = 0;
    }

    // Into the hidden plane 0, through a copy of the plane whose pixels are that buffer; for
    // the true-colour plane the same text, then its ink widened to white 565 words.
    fn caption(self: *const Job, os: *zg.ZigOS) void {
        var fb = os.lfbs[0];
        fb.fb = flip.target(os);
        @memset(fb.fb[IMAGE_H * W .. H * W], 0);
        var buf: [40]u8 = undefined;
        const p = self.picture;
        const stats = std.fmt.bufPrint(&buf, "{d}/{d} {s}: {d} OF {d} COLOURS", .{ p + 1, gallery.NAMES.len, gallery.NAMES[p], gallery.count(p, self.mode + 1), gallery.count(p, 0) }) catch "?";
        os.printText(&fb, gallery.MODES[self.mode].title, 4, IMAGE_H + 2, INK, 0);
        os.printText(&fb, stats, 4, IMAGE_H + 11, INK, 0);
        if (self.kind() == .rgb565) widenCaption(fb.fb, flip.targetTc(os));
    }
};

// The caption band's ink (index INK) as white, the rest black, two pixels a store.
fn widenCaption(ink: [*]const u8, tc: zg.tc.Fb) void {
    for (IMAGE_H..H) |y| {
        var x: usize = 0;
        while (x < W) : (x += 2) {
            const a: u16 = if (ink[y * W + x] == INK) 0xFFFF else 0;
            const b: u16 = if (ink[y * W + x + 1] == INK) 0xFFFF else 0;
            tc.put2(x, y, a, b);
        }
    }
}

// Modes 1 and 2: the index rows as they are (CHISEL from cart RAM, else the CPU).
fn copyRows(os: *zg.ZigOS, idx: []const u8, from: usize, to: usize) void {
    const dst = flip.target(os) + from * W;
    const src = idx[from * W .. to * W];
    if (zg.blit.chisel.copy) |copy| if (copy(dst, W, src.ptr, W, W, to - from, null)) return;
    @memcpy(dst[0..src.len], src);
}

// Mode 3: the RGB565 rows into the true-colour plane (640 bytes a row, CHISEL from cart RAM).
fn copyTcRows(os: *zg.ZigOS, words: []const u8, from: usize, to: usize) void {
    const ROW = 2 * W;
    const dst: [*]u8 = @ptrCast(flip.targetTc(os).pixels);
    const src = words[from * ROW .. to * ROW];
    if (zg.blit.chisel.copy) |copy| if (copy(dst + from * ROW, ROW, src.ptr, ROW, ROW, to - from, null)) return;
    @memcpy(dst[from * ROW ..][0..src.len], src);
}
