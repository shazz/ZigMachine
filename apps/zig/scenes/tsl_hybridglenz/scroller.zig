// --------------------------------------------------------------------------
// perso_scrolltext (screen.js:93-148), a proportional scroller the remake wrote
// by hand because CODEF's own scrolltext classes are fixed-width.
//
// Every number here stays in the remake's 2x units — the offsets, the per-glyph
// widths of tilefont.addSpecial() and the 1.65 px/frame speed — and only the
// destination x is halved. Several of the widths (13, 11, 15) are ODD, so
// halving the table first would round the spacing away.
//
// The text is THE SILENTS', 1993, word for word.
// --------------------------------------------------------------------------
const zg = @import("zigos");
const Blitter = zg.Blitter;
const LogicalFB = zg.LogicalFB;
const A = @import("assets.zig");

pub const TILE_W = 32; // 2x; the glyph BOX, which is wider than most advances
pub const TILE_H = 24;
pub const FIRST_CHAR = 32; // tilefont.initTile(font, 32, 24, 32)
pub const SPEED: f32 = 1.65;

/// tilefont.addSpecial(), indexed by charCode - 32. Anything not named there
/// advances by the full tile, which is what perso_scrolltext.init falls back to.
const ADVANCE = blk: {
    var w = [_]u8{TILE_W} ** 59;
    const specials = .{
        .{ ' ', 13 }, .{ '?', 14 }, .{ '@', 18 }, .{ 'A', 16 }, .{ 'B', 17 }, .{ 'C', 16 },
        .{ 'D', 16 }, .{ 'E', 16 }, .{ 'F', 14 }, .{ 'G', 16 }, .{ 'H', 16 }, .{ 'I', 6 },
        .{ 'J', 12 }, .{ 'K', 16 }, .{ 'L', 14 }, .{ 'M', 26 }, .{ 'N', 16 }, .{ 'O', 16 },
        .{ 'P', 16 }, .{ 'Q', 16 }, .{ 'R', 14 }, .{ 'S', 16 }, .{ 'T', 14 }, .{ 'U', 16 },
        .{ 'V', 16 }, .{ 'W', 26 }, .{ 'X', 18 }, .{ 'Y', 16 }, .{ 'Z', 16 }, .{ '*', 24 },
        .{ '+', 11 }, .{ ',', 6 },  .{ '-', 11 }, .{ '.', 6 },  .{ '0', 16 }, .{ '1', 8 },
        .{ '2', 16 }, .{ '3', 16 }, .{ '4', 16 }, .{ '5', 16 }, .{ '6', 16 }, .{ '7', 14 },
        .{ '8', 16 }, .{ '9', 15 }, .{ ':', 6 },  .{ '!', 6 },  .{ '"', 13 }, .{ '\'', 6 },
    };
    for (specials) |s| w[s[0] - FIRST_CHAR] = s[1];
    break :blk w;
};

const TEXT =
    "                                          *THE SILENTS* ARE BACK WITH A NEW INTRO CALLED" ++
    " *HYBRID GLENZ*.      FIRST OF ALL, THE CREDITS:      CODE AND DESIGN BY SPIROU AND CUDD" ++
    "LEY, GRAPHICS BY CHEVRON AND MUSIC BY BLAIZER.     THIS SMALL INTRO WAS RELEASED TO ANNO" ++
    "UNCE THAT WE, SPIROU AND CUDDLEY, HAVE JOINED THE SILENTS AND ALSO TO SAY WELCOME TO OUR" ++
    " NEW MEMBERS:     ANGEL DAWN, AUTOPSY, JOKER AND MADDOX...     GREETINGS MUST FLY AWAY T" ++
    "O ALL OUR FRIENDS OUT THERE, YOU ALL KNOW WHO YOU ARE, RIGHT?     LOOK OUT FOR MORE SILE" ++
    "NTS PRODUCTIONS IN THE NEAR FUTURE AND REMEMBER THAT 1993 IS OURS!                      " ++
    "     WE MUST SEND SOME PERSONAL HELLOS TO THE FOLLOWING DUDES:     REGULATOR - RELEASE Y" ++
    "OUR TRACKER, NOW!     T.PHRAUD - THANKS FOR LETTING US BORROW YOUR HD!     CRAYON OF NOX" ++
    "IOUS - I'LL SEND YOU THE MANUAL AS SOON AS POSSIBLE!     FAJSER AND ABADDON OF RAGE - SN" ++
    "USMUMRIKAR!      AND ALL MEMBERS OF *SILENTS* - HOPE TO MEET YOU ALL AT THE PARTY IN GOT" ++
    "HENBURG LATER THIS YEAR!!!           SPIROU AND CUDDLEY ARE ALWAYS LOOKING FOR COOL CODE" ++
    "R CONTACTS... SO IF YOU'RE A CODER, FEEL FREE TO WRITE US AT THIS ADDRESS:    DICK AND J" ++
    "EAN ROSTROM, HORNSG. 7:10, 415 03 GOTHENBURG, SWEDEN.            THAT'S ALL FOLKS!!!    " ++
    "                                               ";

/// init() pads the text with floor(720/32)+1 = 23 spaces at each end, and the
/// scroll restarts when curroffset passes length - 23.
const PAD = 23;
const LEN = TEXT.len + 2 * PAD;
const WRAP = LEN - PAD; // curroffset > WRAP -> back to the start

fn charAt(i: usize) u8 {
    if (i < PAD or i >= PAD + TEXT.len) return ' ';
    return TEXT[i - PAD];
}

fn advanceOf(i: usize) i32 {
    return ADVANCE[charAt(i) - FIRST_CHAR];
}

pub const Scroller = struct {
    curr: usize, // curroffset
    pos: f32, // offset[curr].value - scroffset, i.e. the first glyph's x (2x, <= 0)

    pub fn init(self: *Scroller) void {
        self.curr = 0;
        self.pos = 0;
    }

    /// advance(): one step, one character test — the remake's single `if`, not
    /// a loop, which holds because the narrowest advance (6) outruns 1.65.
    pub fn update(self: *Scroller) void {
        self.pos -= SPEED;
        if (self.pos < -@as(f32, @floatFromInt(advanceOf(self.curr)))) {
            self.pos += @floatFromInt(advanceOf(self.curr));
            self.curr += 1;
        }
        if (self.curr > WRAP) {
            self.curr = 0;
            self.pos = 0;
        }
    }

    /// draw(y): glyphs from curroffset until the destination is covered. The
    /// bound is the plane's width rather than the remake's canvas width, since
    /// the bar under the text runs the full raster (borders included).
    pub fn draw(self: *const Scroller, fb: *LogicalFB, bl: *Blitter, font: []const u8, y: i16, width: u16) void {
        const limit: i32 = @as(i32, width) * 2 + TILE_W;
        var x: f32 = self.pos;
        var i = self.curr;
        while (x < @as(f32, @floatFromInt(limit)) and i < LEN) : (i += 1) {
            const tile: u16 = @as(u16, charAt(i) - FIRST_CHAR) * (TILE_W / 2);
            bl.blitImage(fb, @intFromFloat(@round(x / 2)), y, font, A.FONT_W, tile, 0, TILE_W / 2, TILE_H / 2, A.KEY);
            x += @floatFromInt(advanceOf(i));
        }
    }
};
