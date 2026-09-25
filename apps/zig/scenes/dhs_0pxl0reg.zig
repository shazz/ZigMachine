// --------------------------------------------------------------------------
// DHS (Dead Hackers Society) — "(n)0 PIXELS (n)0 REGRETS", Sommarhack 2024,
// zero-bitplane compo. Code EVIL, LOKE; music CRAZY Q, MODMATE; graphics
// COREL, CG (credits from the .nfo).
//
// Ported from the ORIGINAL ST binary (0PXL0REG.PRG, UPX-packed; addresses are
// the unpacked program's, relocated to $10000). Every part was reverse-
// engineered into a Python reference model that matches a full cycle-counted
// run of the demo on 21,939 of its 21,953 frames; the Zig here is that model's
// integer math, part by part (dhs_0pxl0reg/p*.zig).
//
// NO BITPLANES, as in the original: every plane stays disabled and empty. The
// whole picture, borders included, is colour 0 ($FF8240) rewritten while the
// beam crosses the line, here through HW 1.6.0 BEAM: each part's kernel lists
// its cycle-counted move.w's (dhs_0pxl0reg/out.zig maps them to the physical
// frame) and the global HBL queues each line's writes (zg.beam). No write is
// ever refused (REG_BEAM_DROPPED stays 0; the harness proves it).
// OPEN: docs/sealed-loader.js uploads the physical frame only for ENABLED
// planes, and any enabled plane overwrites the window; until the host shows
// the frame with no plane enabled, this screen is blank in the browser. The
// headless harness reads the machine's frame directly and is unaffected.
//
// Seventeen parts on the demo's own sequencer (seq.zig), ~435 s; it ends in P17,
// which runs forever, and so does this. Music: two SNDHs that match the demo's
// YM dumps register for register (hooks.zig).
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;

const seq = @import("dhs_0pxl0reg/seq.zig");
const out = @import("dhs_0pxl0reg/out.zig");

/// The ST's VBL is 50 Hz; the host's frame is whatever the display runs at.
/// The sequencer is music-synced, so it advances by real 20 ms VBLs.
const VBL_US: u32 = 20_000;
const MAX_VBLS_PER_FRAME: u32 = 3; // after a stall, catch up a little, not all of it

pub const Demo = struct {
    vbl_us: u32, // microseconds towards the next VBL

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.vbl_us = 0;
        for (&zigos.lfbs) |*fb| fb.is_enabled = false; // zero bitplanes
        seq.reset();
        zigos.setHBLHandler(out.hbl);
    }

    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        const ms = if (dt > 0 and dt < 1000) dt else 0;
        self.vbl_us += @intFromFloat(ms * 1000);
        var n: u32 = 0;
        while (self.vbl_us >= VBL_US) : (self.vbl_us -= VBL_US) {
            if (n < MAX_VBLS_PER_FRAME) seq.tick();
            n += 1;
        }
    }

    /// Nothing to draw: the HBL paints the frame from the writes tick() listed.
    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = self;
        _ = zigos;
        _ = dt;
    }
};
