// --------------------------------------------------------------------------
// LOCKBUSTER 2 -- the second Lockbuster intro, "for DMA"(1989), the Atari ST
// demo that the Go production github.com/olivierh59500/go-lockbuster2
// ("Lockbuster 2 Go / DMA / 1989") re-created from the original executable.
// This cart is that production, ported to the ZigMachine: the six native
// scroll engines (lockbuster2/engine.zig, transcribed from the Go clock and
// pinned by the Go tree's own RAM checkpoints of the REAL machine), the two
// title slides, the per-line rasters and the toggles the demo itself explains
// in its scrolltext (message-3: "PRESS: F1 GOLD TEXT, F2 METAL TEXT, F3 COLOR
// TEXT, F4 BLACK TEXT, F5 NEW HBL, F6 OLD HBL").
//
// ONE PLANE, THREE COLOUR SOURCES -- exactly the Go shader's decomposition:
//
//   1. The UP/LINE raster: the engine's nibble-0 pixels change colour every
//      OTHER line (the demo rewrote colour register 0 for 100 HBL words over
//      200 lines, which is why the Go shader reads Rasters[y/2]). ST palette
//      entry 0's copper table carries the words of raster-old/new; rows past
//      the table are 0 = black, and the LAST bank rows are black, so the
//      lower half of the screen sits behind the black glyph band. The glass
//      is REAL RASTERS not pixel bars, borders included: entry 0 IS the
//      border's colour on an ST, so the global HBL copies the same table into
//      REG_BACKGROUND per physical line (garfield's borderHbl), and the bars
//      run edge to edge without the plane ever being oversized (wex's rule:
//      the raster runs in the SAME register on both sides of the screen).
//      The background stays black where the table has no words (below line
//      200 and in the top/bottom border bands, i.e. lines 0..39 and 240..279
//      of the physical raster), so the closed border never lies about colour.
//   2. The colour-1 raster, only when ColorText (F3): the Go shader indexed
//      Rasters[row + 9] for ink pixels -- an HBL write of colour 1 nine rows
//      later than colour 0's, and the demo's own per-line ink raster. Entry
//      1 otherwise holds its static palette word (0, black: the metallic
//      glyphs' premise).
//   3. The 16 static palette words (metal vs gold), which indexes 2..15 take:
//      the copper changes NOTHING about them (they are not per line).
//
// The engine's ring buffer is 2 x 128 KB in the machine's RAM pool, and the
// plane fills from the ring's front half every frame: the engine screen is
// 320x200x4 bitplanes INTERLEAVED per word, expanded to the ZigMachine's
// one-plane-per-pixel-index format on the way out.
//
// CONTROLS. F1 gold / F2 metallic text, F3 coloured / F4 black text
// background, F5 new / F6 old HBL table. Space or Escape leaves to the menu
// (the Go demo ends the app on them; a ZigMachine screen hands back to the
// menu instead).
//
// MUSIC: Mad Max's "Rollout" rolls n its own SNDH subtune 1.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const copper = zg.copper;
const engine_mod = @import("lockbuster2/engine.zig");
const Engine = engine_mod.Engine;

// MUSIC (CLAUDE.md: an SNDH, not a YM dump). The production plays music.ym --
// LHA "ROLLOUT1.YM", self-titled "Rollout Tune 1" by Jochen Hippel (= Mad
// Max), YM6 by LeOnArD, 1999 rip. The archive's own Rollout.sndh is the same
// two-tune image: Mad_Max/Games/Rollout.sndh (the Games/SID/ variant is
// ~abdy STE-DMA and plays SILENCE here, the exact trap
// replicants_emlyn documented). Subtune 1 is "Tune 1", the side the demo
// carries; apps/sndh_headless.mjs PASSes both subtunes on the sealed YM.
const MUSIC = "lockbuster2_rollout.sndh";
const MUSIC_TUNE: u8 = 1;

const PLANE = 0;
const W: usize = zg.WIDTH; // 320
const H: usize = zg.HEIGHT; // 200
const PHYS_H: usize = zg.PHYSICAL_HEIGHT; // 280, the global HBL's lines
const VBORDER: usize = zg.VERTICAL_BORDERS_HEIGHT; // 40

const K_ESC: u32 = 0xE012;
const K_F1: u32 = 0xE001;
const K_F2: u32 = 0xE002;
const K_F3: u32 = 0xE003;
const K_F4: u32 = 0xE004;
const K_F5: u32 = 0xE005;
const K_F6: u32 = 0xE006;
const K_SPACE: u32 = 32;

/// One host frame steps at most this many 50 Hz engine VBLs, so a stalled tab
/// never replays a minute of the intro on real time (naos_nitrowave's pacing).
const VBL_MS: f32 = 20;
const MAX_VBLS: i8 = 6;

// The demo's own 16 colour words in metallic and gold (Go's `words` arrays,
// quoted; gold turned on by the slide-in bank and stays on).
const WORDS = [16]u16{ 0x000, 0x000, 0x134, 0x235, 0x124, 0x023, 0x346, 0x245, 0x356, 0x457, 0x467, 0x567, 0x677, 0x577, 0x701, 0x777 };
const WORDS_GOLD = [16]u16{ 0x000, 0x000, 0x341, 0x532, 0x421, 0x320, 0x643, 0x542, 0x653, 0x754, 0x764, 0x765, 0x776, 0x775, 0x107, 0x777 };

/// Go's put(): an ST colour word to RGBA on the channels-nibble*34 scale the
/// Go production rendered at.
fn wordColor(w: u16) Color {
    return .{
        .r = @intCast(((w >> 8) & 7) * 34),
        .g = @intCast(((w >> 4) & 7) * 34),
        .b = @intCast((w & 7) * 34),
        .a = 255,
    };
}

const BLACK = wordColor(0x000);

/// The raster bank the demo's HBL table holds: one word per SECOND screen
/// line (the shader's floor(y/2)), `rasterWord` returning 0 past the bank
/// end exactly as the Go uniform did.
fn rasterColor(engine: *const Engine, bank: usize, y: usize) u32 {
    return wordColor(engine.rasterWord(bank, y / 2)).toRGBA();
}

// --------------------------------------------------------------------------
// The scene's copper (0: the bars full width via entry 0; 1: the ink) and
// the global border HBL, both table-driven exactly like replicants_garfield.
// --------------------------------------------------------------------------
const SLOT0: copper.Slot = 0; // ST palette entry 0
const SLOT1: copper.Slot = 1; // ST palette entry 1

var copper_tables: [2]copper.Table = undefined;
var border_table: [PHYS_H]u32 = undefined;

/// Global HBL, PHYSICAL lines 0..279: the border takes the bars' colour for
/// the line, black outside the visible band. One frame ahead of the plane is
///NOT owed here: the table only changes when a key or a phase turns a
/// toggle, and update(refresh) and border_table are set in the same render
/// pass that fills the plane (garfield built its table one frame ahead for
/// MOVING bars; these bars never move of their own accord).
fn borderHbl(zigos: *ZigOS, line: u16) void {
    zigos.setBackgroundColor(Color.fromRGBA(border_table[@min(line, border_table.len - 1)]));
}

/// The engine ring and the exports the harness holds everything through --
/// draw time details stay behind, present() writes the plane and the copper
/// from the same engine state the exports expose.
var g_engine: Engine = undefined;
var g_ready = false;

/// The harness's window into the ring: the exact bytes present() shows, so
/// the seven checkpoints hold byte for byte against the Go tree's gzipped
/// snapshots of the real machine. 0 = not ready, never dereferenced.
fn screenExport() callconv(.c) u32 {
    if (!g_ready) return 0;
    return @intFromPtr(g_engine.screen().ptr);
}

/// phase(0..7) | gold<<19 | color_text<<20 | new_raster<<21 | tag 0x6a<<22.
fn stateExport() callconv(.c) u32 {
    if (!g_ready) return 0;
    const p: u32 = @intCast(@mod(g_engine.phase, engine_mod.MAX_PHASES));
    return p |
        (@as(u32, @intFromBool(g_engine.gold)) << 19) |
        (@as(u32, @intFromBool(g_engine.color_text)) << 20) |
        (@as(u32, @intFromBool(g_engine.new_raster)) << 21) |
        (0x6A << 22);
}

fn tickExport() callconv(.c) u32 {
    if (!g_ready) return 0;
    return @intCast(g_engine.tick);
}

comptime {
    if (@import("../cart.zig").Cart == Demo) {
        @export(&screenExport, .{ .name = "lb2Screen" });
        @export(&stateExport, .{ .name = "lb2State" });
        @export(&tickExport, .{ .name = "lb2Tick" });
    }
}

fn fail(why: []const u8) void {
    zg.Console.log("lockbuster2: {s}", .{why});
}

// --------------------------------------------------------------------------
// The 32000 engine bytes -> the plane palette indices. One engine row is 160
// bytes = 20 chunks of 8 bytes; a chunk is 4 plane words (2 bytes = 16
// pixels) interleaved p0,p1,p2,p3, and Go Pixels()' loop is the same order:
// at + p*2 + half picks the plane byte, bit 7..0 picks the plane bit.
// --------------------------------------------------------------------------
fn present(engine: *const Engine, fb: *zg.LogicalFB) void {
    const screen = engine.screen();
    const px = fb.fb[0 .. W * H];
    for (0..H) |y| {
        const row = screen[y * 160 ..][0..160];
        const line = px[y * W ..][0..W];
        for (0..20) |block| {
            const at = block * 8;
            for (0..2) |half| {
                const p0 = row[at + half];
                const p1 = row[at + half + 2];
                const p2 = row[at + half + 4];
                const p3 = row[at + half + 6];
                var bit: usize = 0;
                while (bit < 8) : (bit += 1) {
                    const shift: u3 = @intCast(7 - bit);
                    var v: u8 = (p0 >> shift) & 1;
                    v |= ((p1 >> shift) & 1) << 1;
                    v |= ((p2 >> shift) & 1) << 2;
                    v |= ((p3 >> shift) & 1) << 3;
                    line[block * 16 + half * 8 + bit] = v;
                }
            }
        }
    }
}

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {
    ok: bool,
    acc: f32,
    /// demo_main polls this to hand the screen back to the menu (Space/Escape).
    wants_quit: bool,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        // A cart's Demo arrives zeroed: every field set here, never by default.
        self.ok = false;
        self.acc = 0;
        self.wants_quit = false;

        g_engine.init(
            .{ zg.mem.mustAlloc(u8, engine_mod.BUFFER_BYTES), zg.mem.mustAlloc(u8, engine_mod.BUFFER_BYTES) },
            .{ zg.mem.mustAlloc(u8, engine_mod.HEADER_BYTES), zg.mem.mustAlloc(u8, engine_mod.HEADER_BYTES) },
            zg.mem.mustAlloc(u8, engine_mod.COMPILED_BYTES),
        );
        g_ready = true;

        zigos.setBackgroundColor(BLACK);
        const fb = &zigos.lfbs[PLANE];
        fb.is_enabled = true;
        self.refreshPalette(fb);
        // Two copper slots (entries 0 and 1), no border flicker: the plane
        // VISes 320x200 and the border follows colour register 0, as on the ST.
        copper.install(fb, &.{ 0, 1 }, &copper_tables, .{});
        zigos.setHBLHandler(borderHbl);
        @memset(fb.fb[0 .. W * H], 0);

        zg.requestSongTune(MUSIC, MUSIC_TUNE);
        self.ok = true;
    }

    /// The 16 static words do NOT move per line, so their palette write is
    /// plain setPaletteEntry work; entries 0 and 1 get per-line colours from
    /// the copper tables and their BASE colours come from here too.
    fn refreshPalette(self: *Demo, fb: *zg.LogicalFB) void {
        _ = self;
        const words = if (g_engine.gold) WORDS_GOLD else WORDS;
        for (words, 0..) |w, i| fb.palette[i] = wordColor(w).toRGBA();
        for (16..256) |i| fb.palette[i] = 0; // unused above 16: transparent, never shown
    }

    /// The state-dependent tables: entry 0's and entry 1's per-visible-line
    /// colours, and the border. Cheap enough to rebuild every rendered frame
    /// (200 rows x a nibble shift), and simpler to trust than a dirty flag.
    fn refreshLines(self: *Demo, fb: *zg.LogicalFB) void {
        _ = self;
        const bank: usize = if (g_engine.new_raster) 1 else 0;
        const copper0 = copper.visible(fb, SLOT0);
        const copper1 = copper.visible(fb, SLOT1);
        for (0..H) |y| {
            copper0[y] = rasterColor(&g_engine, bank, y);
            // Entry 1: the ink raster nine rows later than colour 0's, when
            // the text is coloured; black otherwise (the metallic words).
            copper1[y] = if (g_engine.color_text)
                wordColor(g_engine.rasterWord(bank, y / 2 + 9)).toRGBA()
            else
                wordColor(0).toRGBA();
        }
        // The border: the same colour-0 words over the visible band, black
        // everywhere else -- top and bottom bands show register 0 black, as
        // the demo's own palette before the rasters wrote it.
        @memset(&border_table, BLACK.toRGBA());
        const band = border_table[VBORDER .. VBORDER + H];
        for (0..H) |y| band[y] = rasterColor(&g_engine, bank, y);
    }
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        _ = self;
        // The engine steps in render(), with the tables it drives: update()
        // owns nothing of its own state (the demo moves only on its VBLs).
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        if (!self.ok) return;
        self.acc = @min(self.acc + dt, VBL_MS * @as(f32, @floatFromInt(MAX_VBLS)));
        while (self.acc >= VBL_MS) : (self.acc -= VBL_MS) g_engine.step();
        self.refreshPalette(&zigos.lfbs[PLANE]);
        self.refreshLines(&zigos.lfbs[PLANE]);
        present(&g_engine, &zigos.lfbs[PLANE]);
    }

    /// F1..F6 exactly as the demo's own scrolltext advertises them. Declaring
    /// key() owns every key, so Escape is honoured here and hands back to the
    /// menu (the contract demo_main.zig spells out); the original demo ended
    /// the program on Space too, and Space here does the same as Escape.
    pub fn key(self: *Demo, cp: u32) void {
        switch (cp) {
            K_F1 => g_engine.gold = true,
            K_F2 => g_engine.gold = false,
            K_F3 => g_engine.color_text = true,
            K_F4 => g_engine.color_text = false,
            K_F5 => g_engine.new_raster = true,
            K_F6 => g_engine.new_raster = false,
            K_ESC, K_SPACE => self.wants_quit = true,
            else => {},
        }
    }
};
