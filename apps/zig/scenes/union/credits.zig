// --------------------------------------------------------------------------
// Union main — the credits pages (efmain.js this.credits + write_text). 8 pages
// of 5 lines each, drawn in the 9x10 credits font with a drop shadow, faded
// in/out on plane 1 over an 800-frame cycle. Text is verbatim from efmain.js.
//
// Font: shared 9x10 credits font (see creditfont.zig), drawn in dedicated,
// palette-alpha-faded P1 slots so it never disturbs the runner/dragonball colours.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const cf = @import("creditfont.zig");

const LINE_PITCH: i16 = 16;
const OX: i16 = 38; // page origin (phys) — Codef (60,36) halved
const OY: i16 = 23;

// Tunable drop-shadow offset (Matt: "set a constant for the shadow thing").
const SHADOW_DX: i16 = 2;
const SHADOW_DY: i16 = 2;

const FACE: u8 = 0x30; // dedicated P1 palette slots (clear of runner 1..7 / ghosts 16..47 / balls 64..192)
const SHADOW: u8 = 0x31;

// 800-frame page cycle (efmain.js greetzTimer): hidden until 200, fade-in over
// ~30f, hold to 600, fade-out over ~30f, next page at 800.
const T_IN: u32 = 200;
const T_OUT: u32 = 600;
const T_PAGE: u32 = 800;
const FADE_STEP: f32 = 1.0 / 30.0;

const PAGES = [8][5][]const u8{
    .{ "  Welcome to the new TRSI and WAB demo", "", "   Please use 1-6 to change the zik", "     (only Chrome or browser die)", "       And enjoy the show !!!!!" },
    .{ "****************************************", "*    This project deserved a place", "*     to credit the various people", "* who have helped and gave their time", "****************************************" },
    .{ "Code.....................TotorMan, Shazz", "Gfx........C-Rem/MJJ, Joe & Thorion/TRSi", "...Dr Satan/Empire, SoLO/WAB, Seen/Melon", "Music........Jess/OVR, Lap/Next, TAO/ACF", ".............505/Checkpoint, Big Alec/DF" },
    .{ "****************************************", "*        The UNION DEMO Remake", "*      All original music and gfx", "*  were reused, here are the credits:", "****************************************" },
    .{ "Intro screen.............Shazz, NoNameNo", "Loader.............................Shazz", "Main menu..........................Shazz", "TCB 1...................MellowMan, Shazz", "Delta Force.............MellowMan, Shazz" },
    .{ "TNT Crew 3...............TotorMan, Shazz", "TCB 2..............................Shazz", "TNT Crew 1.........................Shazz", "The Replicants.....................Shazz", "TNT Crew 2.........................Shazz" },
    .{ "", "Level 16................MellowMan, Shazz", "TCB 3..........TotorMan, NoNameNo, Shazz", "Hidden Screen......................Shazz", "TEX Copier..............MellowMan, Shazz" },
    .{ "", "", "     Now you can press the spacebar", "     and play with the Web version", "          of the Union Demo *" },
};

pub const Credits = struct {
    timer: u32 = 0,
    page: usize = 0,
    alpha: f32 = 0,

    pub fn init(self: *Credits, zigos: *ZigOS) void {
        self.* = .{};
        setAlpha(zigos, 0);
    }

    pub fn update(self: *Credits, zigos: *ZigOS) void {
        self.timer += 1;
        if (self.timer >= T_IN and self.timer < T_IN + 30) {
            self.alpha = @min(1.0, self.alpha + FADE_STEP);
        } else if (self.timer >= T_OUT and self.timer < T_OUT + 30) {
            self.alpha = @max(0.0, self.alpha - FADE_STEP);
        }
        if (self.timer >= T_PAGE) {
            self.timer = 0;
            self.alpha = 0;
            self.page = (self.page + 1) % PAGES.len;
        }
        setAlpha(zigos, @intFromFloat(self.alpha * 255.0));
    }

    pub fn draw(self: *const Credits, zigos: *ZigOS) void {
        if (self.alpha <= 0.0) return;
        const p1: *LogicalFB = &zigos.lfbs[1];
        for (PAGES[self.page], 0..) |line, i| {
            const y = OY + @as(i16, @intCast(i)) * LINE_PITCH;
            cf.drawLine(p1, line, OX + SHADOW_DX, y + SHADOW_DY, SHADOW);
            cf.drawLine(p1, line, OX, y, FACE);
        }
    }
};

fn setAlpha(zigos: *ZigOS, a: u8) void {
    const p1: *LogicalFB = &zigos.lfbs[1];
    p1.setPaletteEntry(FACE, Color{ .r = 255, .g = 255, .b = 255, .a = a });
    p1.setPaletteEntry(SHADOW, Color{ .r = 33, .g = 32, .b = 82, .a = a });
}
