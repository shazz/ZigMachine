// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const readU16Array = @import("../utils/loaders.zig").readU16Array;
const readI16Array = @import("../utils/loaders.zig").readI16Array;
const convertU8ArraytoColors = @import("../utils/loaders.zig").convertU8ArraytoColors;

const ZigOS = @import("../zigos.zig").ZigOS;
const LogicalFB = @import("../zigos.zig").LogicalFB;
const Color = @import("../zigos.zig").Color;
const RenderTarget = @import("../zigos.zig").RenderTarget;


const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const Sprite = @import("../effects/sprite.zig").Sprite;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

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
const back_mask_pal = convertU8ArraytoColors(@embedFile("../assets/screens/reps4/back_mask_pal.dat"));
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
var raster_index: u8 = 0;
var logo_raster_pos: i16 = 0;
var logo_raster_dir: i16 = 1;

pub const Raster = struct {
    position: u16 = undefined,
    direction: i8 = undefined,
    colors: [256]Color = undefined,
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

        for(rasters) |raster| {
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
        fb.setPaletteEntry(1, logo_rasters_b[(line + @intCast(u16, logo_raster_pos)) % 30]);
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
    back_bottom_mask: Sprite = undefined,
    logo: Sprite = undefined,
    logo_offset_table: [256]i16 = undefined,
    table_index: u16 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane for rasters
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
  
        fb.setPalette(back_top_pal);
        fb.setPaletteEntry(255, Color{ .r = 255, .g = 255, .b = 255, .a = 0 });
        self.back_top.init(fb.getRenderTarget(), back_top_b, 320, 31, 0, 0, null, null); 
        self.back_bottom.init(fb.getRenderTarget(), back_bottom_b, 320, 53, 0, 200-54, null, null); 

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_rasterbars); 



        rasters[0] = Raster{.position=40+25+0,   .direction=1,  .colors=blue_rasters_b};
        rasters[1] = Raster{.position=40+25+50,  .direction=1,  .colors=pink_rasters_b};
        rasters[2] = Raster{.position=40+25+100, .direction=1,  .colors=yellow_rasters_b};
        rasters[3] = Raster{.position=40+96,     .direction=-1, .colors=gray_rasters_b};        

        // second plane for backs and logo
        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
       
        var i: usize = 0;
        const f_per: f32 = @intToFloat(f32, self.logo_offset_table.len);
        var f_inc: f32 = 0;

        while(i < self.logo_offset_table.len) : ( i += 1) {
            const f_sin: f32 = 2 * @sin(f_per*2*std.math.pi + f_inc);
            self.logo_offset_table[i] = @floatToInt(i16, f_sin);
            f_inc += 0.15;
            Console.log("{}", .{f_sin});
        }
            
        fb.setPaletteEntry(1, Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); 
        self.logo.init(fb.getRenderTarget(), logo_b, 268, 105, (320-268)/2, 35, &self.logo_offset_table, null); 

        // HBL Handler for the raster effect
        fb.setFrameBufferHBLHandler(0, handler_logo);      

        fb = &zigos.lfbs[2];
        fb.is_enabled = true; 
        fb.setPalette(fonts_mask_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); 
        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, SCROLL_POS, null, null, null);

        fb = &zigos.lfbs[3];
        fb.is_enabled = true; 
        fb.setPalette(back_mask_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); 
        fb.setPaletteEntry(255, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });       
        self.back_bottom_mask.init(fb.getRenderTarget(), back_bottom_mask_b, 320, 53, 0, 200-54, null, null); 

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

        for(rasters) |*raster| {
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

        var fb = &zigos.lfbs[0];
        fb.clearFrameBuffer(0);

        self.back_top.render(null);
        self.back_bottom.render(null);

        self.logo.target.clearFrameBuffer(0);
        self.logo.render(null);

        fb = &zigos.lfbs[2];
        fb.clearFrameBuffer(0);
        self.scrolltext.render();

        var i: usize = SCROLL_POS * WIDTH;
        var tx: usize = (SCROLL_POS - 159) * WIDTH;
        while(i < (SCROLL_POS * WIDTH) + (WIDTH * SCROLL_CHAR_HEIGHT)) : ( i += 1) {         
            fb.fb[i] = fb.fb[i] & fonts_mask_b[tx];
            tx += 1;
        }

        self.back_bottom_mask.render(null);

        _ = elapsed_time;

    }
};
