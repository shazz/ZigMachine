// --------------------------------------------------------------------------
// ARE YOU SITTING COMFORTABLY? (Reservoir Gods, Falcon 030, 2004; code Damo, graphics SH3,
// music MSG, particles Mr Pink, screen modes / replay / ball-oid EarX). Matt's favourite intro,
// ported from the depacked program: prototypes/falcon_ays_re/ANALYSIS.md says how each part
// works and how it maps onto KESTREL.
//
// The MOD is the script. Its 164 `8xx` commands (falcon_ays/script.zig) each select one of the
// demo system's routine triples (falcon_ays/fx.zig): a screen mode and a part. The song's clock
// fires each command on its row (falcon_ays/show.zig), so the parts change on the beats where
// Damo placed them, and runs each part's timer slot at the replay's 50 Hz.
//
// One true-colour plane, double-buffered (falcon_ays/screen.zig): mode 804 = 320x200, mode 805
// = 160x100 doubled (pixel pairs, lines doubled by the copper list).
//
// Music: docs/music/falcon_ays.mod, MSG's COMFORT.MOD (byte for byte the one in the program).
// The pictures, textures and tables are the original's (falcon_ays/art.zig, ripped by
// tools/falcon_ays_art.py into apps/zig/assets/screens/falcon_ays/; published, Matt 3 Nov 2026).
// Escape leaves.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const script = @import("falcon_ays/script.zig");
const art = @import("falcon_ays/art.zig");
const Show = @import("falcon_ays/show.zig").Show;
const ZigOS = zg.ZigOS;

pub const SONG = "falcon_ays.mod";
const K_ESC: u32 = 0xE012; // demo_main.zig's code for Escape

pub const Demo = struct {
    show: Show,
    frame: u32 = 0,
    ticks: u32 = 0, // song position, 50 Hz ticks
    cursor: script.Cursor = .{},
    wants_quit: bool = false,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        self.* = .{ .show = Show.init(zigos) };
        art.announce();
        zg.requestSong(SONG);
    }

    pub fn key(self: *Demo, cp: u32) void {
        if (cp == K_ESC) self.wants_quit = true;
    }

    /// The song's clock: every 50 Hz tick due this frame fires the commands of the rows it
    /// reaches and runs the timer slot. While the MOD plays, its own position (zigos.song_ms,
    /// mirrored by the host from the audio thread, on the board from BARD) is the clock; with
    /// no sound (no local file, or sound not enabled yet) the frame count is.
    pub fn update(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = dt;
        self.frame += 1;
        const playing = zigos.song_ms != 0;
        const due = if (playing) zigos.song_ms / 20 else script.ticksAt(self.frame);
        if (playing and due + 50 < self.ticks) self.rewind(); // the music started over
        while (self.ticks < due) {
            self.ticks += 1;
            const row = self.ticks / script.TICKS_PER_ROW;
            if (row >= script.SONG_ROWS) return self.restart();
            while (self.cursor.next(row)) |v| self.show.command(v);
            self.show.tick();
        }
    }

    pub fn render(self: *Demo, zigos: *ZigOS, dt: f32) void {
        _ = zigos;
        _ = dt;
        self.show.render();
    }

    // The song's end: the show and the music start again.
    fn restart(self: *Demo) void {
        self.rewind();
        zg.requestSong(SONG);
    }

    fn rewind(self: *Demo) void {
        self.frame = 0;
        self.ticks = 0;
        self.cursor = .{};
        self.show.command(0x07);
    }
};
