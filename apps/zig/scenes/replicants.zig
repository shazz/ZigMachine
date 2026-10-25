// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const readU16Array = zg.readU16Array;
const readI16Array = zg.readI16Array;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const ZigOS = zg.ZigOS;
const LogicalFB = zg.LogicalFB;
const Color = zg.Color;
const RenderTarget = zg.RenderTarget;


const Scrolltext = zg.Scrolltext;
const Sprite = zg.Sprite;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// scrolltext
const fonts_b = @embedFile("../assets/screens/reps4/fonts.raw");
const SCROLL_TEXT = "                       THE UNION PRESENTS : - GARFIELD - CRACKED BY DOM FROM THE REPLICANTS MEMBER OF THE UNION. MEMBERS OF THE REPLICANTS ARE : ELWOOD(NEW MEMBER!!),DOM,<R.AL>,SNAKE,COBRA,KNIGHT 2OO1,GO HAINE,EXCALIBUR,RANK-XEROX,HANNIBAL,GOLDORAK...... HI TO : LOCKBUSTERS,THE BLADE RUNNERS,B.O.S.S,WAS (NOT WAS),MCA,THE PREDATORS     A SPECIAL HI TO ALL MEMBERS OF THE MICRO CLUB LILLOIS!!!!!!!!........BYE BYE.......SEE YOU A NEXT TIME....";
const SCROLL_CHAR_WIDTH = 16; 
const SCROLL_CHAR_HEIGHT = 16;
const SCROLL_SPEED = 2;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = (320/SCROLL_CHAR_WIDTH) + 1;
const SCROLL_POS = 169;

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/reps4/fonts_pal.dat"));
const back_top_pal = convertU8ArraytoColors(@embedFile("../assets/screens/reps4/back_top_pal.dat"));
const fonts_mask_pal = convertU8ArraytoColors(@embedFile("../assets/screens/reps4/fonts_mask_pal.dat"));

// rasters
const logo_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/reps4/rasterFonts_pal.dat"));
const yellow_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/reps4/rasterYellow_pal.dat"));
const pink_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/reps4/rasterPink_pal.dat"));
const gray_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/reps4/rasterGray_pal.dat"));
const blue_rasters_b = convertU8ArraytoColors(@embedFile("../assets/screens/reps4/rasterBlue_pal.dat"));

// sprites
const back_top_b = @embedFile("../assets/screens/reps4/back_top.raw");
const back_bottom_b = @embedFile("../assets/screens/reps4/back_bottom.raw");
const back_bottom_mask_b = @embedFile("../assets/screens/reps4/back_mask.raw");
const fonts_mask_b = @embedFile("../assets/screens/reps4/fonts_mask.raw");
const logo_b = @embedFile("../assets/screens/reps4/logo.raw");

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
// The scroller's mask rows (fonts_mask.raw rows 10..25, the 16 rows the AND below
// covers) as aligned 32-bit words, built at compile time, so the per-frame AND is
// one load/store per 4 pixels instead of per byte through a byte-aligned embed.
const MASK_FIRST: usize = (SCROLL_POS - 159) * WIDTH;
const MASK_WORDS: usize = WIDTH * SCROLL_CHAR_HEIGHT / 4;
// back_mask.raw (the bottom picture's foreground, drawn ABOVE the scroller) is folded
// in too: where it is opaque the mask byte is 0, so the scroller is transparent there
// and plane 0 shows through. Every opaque back_mask pixel has exactly the colour of
// the back_bottom pixel under it (same RGB, other index), so the composed frame is
// the same (the logo plane between them never reaches row 146) and the mask needs no
// plane of its own: one FRESCO pass, ~0.8 Mc a frame, saved.
const BACK_MASK_FIRST: usize = (SCROLL_POS - BACK_BOTTOM_Y) * WIDTH;
const BACK_BOTTOM_Y: usize = 200 - 54;
const mask_words: [MASK_WORDS]u32 = blk: {
    @setEvalBranchQuota(100_000);
    var w: [MASK_WORDS]u32 = undefined;
    for (&w, 0..) |*x, i| {
        var bytes: [4]u8 = fonts_mask_b[MASK_FIRST + i * 4 ..][0..4].*;
        for (&bytes, 0..) |*b, k| {
            if (back_bottom_mask_b[BACK_MASK_FIRST + i * 4 + k] != 0) b.* = 0;
        }
        x.* = std.mem.readInt(u32, &bytes, .little);
    }
    break :blk w;
};

// Logo sprite geometry (Sprite.init in Demo.init) for the blitter path.
const LOGO_W: u16 = 268;
const LOGO_H: u16 = 105;
const LOGO_X: i32 = (320 - 268) / 2;
const LOGO_Y: i32 = 35;

var raster_index: u8 = 0;
var blitter: zg.Blitter = .{};
var logo_drawn_idx: u16 = 0xFFFF; // the table index the logo plane currently shows
var logo_raster_pos: i16 = 0;
var logo_raster_dir: i16 = 1;

pub const Raster = struct {
    position: u16 = undefined,
    direction: i8 = undefined,
    // align(4): a Color is read as one u32, and after position + direction the
    // array sat 2 mod 4 (a misaligned access traps on the board, 44 a frame).
    colors: [256]Color align(4) = undefined,
};

var rasters: [4]Raster = undefined;


// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
fn handler_rasterbars(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {

    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if( (line >= rasters[0].position and line < rasters[0].position + 11) or 
        (line >= rasters[1].position and line < rasters[1].position + 11) or 
        (line >= rasters[2].position and line < rasters[2].position + 11) or
        (line >= rasters[3].position and line < rasters[3].position + 11) ) {

        for(&rasters) |*raster| {
            if(line >= raster.position and line < raster.position + 11) {
                fb.setPaletteEntry(0, raster.colors[line - raster.position]);
                fb.setPaletteEntry(255, raster.colors[line - raster.position]);
            }
        }
    } else {
        fb.setPaletteEntry(0, back_color);
        fb.setPaletteEntry(255, back_color);
    }

    _ = col;
    _ = zigos;
}

fn handler_logo(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    const back_color: Color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

    if (line >= 40+logo_raster_pos and line < 40+29+logo_raster_pos ) {
        fb.setPaletteEntry(1, logo_rasters_b[(line + @as(u16, @intCast(logo_raster_pos))) % 30]);
    }
    else {
        fb.setPaletteEntry(1, back_color);
    }

    _ = col;
    _ = zigos;
}

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    back_top: Sprite = undefined,
    back_bottom: Sprite = undefined,
    logo: Sprite = undefined,
    logo_offset_table: [256]i16 = undefined,
    table_index: u16 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // A cart re-entered from the menu inherits the previous cart's bytes, so
        // struct defaults and module-scope initialisers cannot be trusted: reset here.
        self.name = 0;
        self.frame_counter = 0;
        self.table_index = 0;
        raster_index = 0;
        logo_raster_pos = 0;
        logo_raster_dir = 1;
        logo_drawn_idx = 0xFFFF;
        blitter.init();

        // first plane for rasters
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
  
        fb.setPalette(back_top_pal);
        fb.setPaletteEntry(255, Color{ .r = 255, .g = 255, .b = 255, .a = 0 });
        self.back_top.init(fb.getRenderTarget(), back_top_b, 320, 31, 0, 0, null, null); 
        self.back_bottom.init(fb.getRenderTarget(), back_bottom_b, 320, 53, 0, 200-54, null, null); 
        // Both pictures are static (the raster is palette writes from the HBL):
        // draw them once. A zero pixel is skipped or written as 0 on a plane that
        // is already 0, so the first frame cannot differ either way.
        self.back_top.render(null);
        self.back_bottom.render(null);

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandlerPure(0, handler_rasterbars); 



        rasters[0] = Raster{.position=40+25+0,   .direction=1,  .colors=blue_rasters_b};
        rasters[1] = Raster{.position=40+25+50,  .direction=1,  .colors=pink_rasters_b};
        rasters[2] = Raster{.position=40+25+100, .direction=1,  .colors=yellow_rasters_b};
        rasters[3] = Raster{.position=40+96,     .direction=-1, .colors=gray_rasters_b};        

        // second plane for backs and logo
        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
       
        var i: usize = 0;
        const f_per: f32 = @as(f32, @floatFromInt(self.logo_offset_table.len));
        var f_inc: f32 = 0;

        while(i < self.logo_offset_table.len) : ( i += 1) {
            const f_sin: f32 = 2 * @sin(f_per*2*std.math.pi + f_inc);
            self.logo_offset_table[i] = @as(i16, @intFromFloat(f_sin));
            f_inc += 0.15;
            Console.log("{}", .{f_sin});
        }
            
        fb.setPaletteEntry(1, Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); 
        self.logo.init(fb.getRenderTarget(), logo_b, 268, 105, (320-268)/2, 35, &self.logo_offset_table, null); 

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandlerPure(0, handler_logo);      

        fb = &zigos.lfbs[2];
        fb.is_enabled = true; 
        fb.setPalette(fonts_mask_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); 
        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, SCROLL_POS, null, null, null);

        // No fourth plane: back_mask.raw lives in mask_words (see there).
        zigos.lfbs[3].is_enabled = false;

        self.table_index = 0;

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();

        if (self.table_index == self.logo_offset_table.len) self.table_index = 0;
        self.logo.update(null, null, self.table_index, null);
        
        self.frame_counter += 1;
        if (self.frame_counter == 2) {
            raster_index += 1;
            self.frame_counter = 0;
            self.table_index += 1;
        }

        for(&rasters) |*raster| {
            if(raster.direction == 1) {
                raster.position += 1;
                if (raster.position > 135+40) raster.direction = -1;
            } else {
                raster.position -= 1;
                if (raster.position < 25+40) raster.direction = 1;
            }
        }

        logo_raster_pos += logo_raster_dir;
        if(logo_raster_pos == 140) logo_raster_dir = -1;
        if(logo_raster_pos == 0) logo_raster_dir = 1;


        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {
        self.renderLogo(&zigos.lfbs[1]);

        // The scroller draws on rows 169..184 only: CHISEL clears those.
        const fb = &zigos.lfbs[2];
        blitter.fill(fb, 0, SCROLL_POS, WIDTH, SCROLL_CHAR_HEIGHT, 0);
        self.scrolltext.render();

        const strip: []u32 = @as([*]u32, @ptrCast(@alignCast(fb.fb + SCROLL_POS * WIDTH)))[0..MASK_WORDS];
        for (strip, mask_words) |*px, m| px.* &= m;

        _ = elapsed_time;
    }

    // The logo sprite shifts each ROW sideways by logo_offset_table[(idx + row)
    // % 256], and Sprite.render ADDS the shift to its running offset, so row r
    // sits at the sum of the shifts above it (the drift is part of the look).
    // It only changes when table_index does (every other frame): then each row
    // is one keyed CHISEL blit instead of 28k Sprite pixel stores.
    fn renderLogo(self: *Demo, fb: *LogicalFB) void {
        const idx: u16 = self.logo.x_offset_index; // what update() gave the sprite (before table_index stepped)
        if (idx == logo_drawn_idx) return;
        logo_drawn_idx = idx;
        // rows 34 and 141 too: a row pushed off an edge wraps onto its neighbour
        blitter.fill(fb, 0, LOGO_Y - 1, WIDTH, LOGO_H + 2, 0);
        var x: i32 = LOGO_X;
        for (0..LOGO_H) |r| {
            const row = logo_b[r * LOGO_W ..][0..LOGO_W];
            const y: i32 = LOGO_Y + @as(i32, @intCast(r));
            if (x >= 0 and x + LOGO_W <= WIDTH) {
                blitter.blitImage(fb, @intCast(x), @intCast(y), logo_b, LOGO_W, 0, @intCast(r), LOGO_W, 1, 0);
            } else {
                wrapRow(fb, row, y * WIDTH + x);
            }
            x += self.logo_offset_table[(idx + r) % self.logo_offset_table.len];
        }
    }

    // A row that leaves the plane's edge continues on the neighbouring row, as
    // the sprite's linear offset did.
    fn wrapRow(fb: *LogicalFB, row: []const u8, at: i32) void {
        for (row, 0..) |px, i| {
            if (px != 0) fb.fb[@intCast(at + @as(i32, @intCast(i)))] = px;
        }
    }
};
