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

const Scrolltext = @import("../effects/scrolltext.zig").Scrolltext;
const Background = @import("../effects/background.zig").Background;
const Sprite = @import("../effects/sprite.zig").Sprite;
const Bobs = @import("../effects/bobs.zig").Bobs;

const Console = @import("../utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = @import("../zigos.zig").HEIGHT;
const WIDTH: u16 = @import("../zigos.zig").WIDTH;

// scrolltext
const fonts_b = @embedFile("../assets/screens/equinox/fonts.raw");
const SCROLL_TEXT = "            EQUINOX PRESENTS RVF HONDA CRACKED BY ILLEGAL ,INTRO CODED BY KRUEGER ( HE IS NOT HERE BECAUSE HE WORKS AS DUSTMAN,DON'T LAUGH THAT'S REAL ) ,GRAPHIXX BY SMILEY ,ACRONYM BY EIDOLON...             MEMBERS OF EQUINOX ARE :COMPUTER JONES,CREENOX,EIDOLON,ELIAS,ILLEGAL,KRUEGER ( HEHEHE! ),SMILEY,STEPRATE,TDS ( DROP YOUR GIRL FRIEND AND COME HOME ),WEREWOLF ,ZOOLOOK.            GREETINGS TO :MDK (SEE YOU SOON),ST CNX ( WHEN WILL ARRIVE THE TETARD DEMO ),MCA ( HELLO HARRIE ),THE REPLICANTS  ( GOOD INTRO FURY ),DMA ( CHON CHON AND CAMERONE ),THE OVERLANDERS ( BIG THANKS FOR SWAPPING US !),SECTOR NINETY NINE,MEGABUGS,MCS,TBC ( HI DOC )...            HI TO : SID,TOXIC,CHUD,RED SHARK,INFERNAL CODER,BEGON JAUNE,TRAHISON (HE TOI LA BAS ,POURQUOI TU MARCHES COMME CA ? C EST LE RAP,RAP DES GARCONS BOUCHER),POKE,BO,MAGNUM FORCE,FISHERMAN,JULES,BUB,TESTO,EXCALIBURP,JOHNNY TGB,ALX,STRIDER,NOBRU,BABEBIBOBU GROUP,CHRISTINA AND GWENDOLINE FROM ST RANGE...            MESSAGE FROM STEPRATE :TU CONNAIS RIGOULOSS ? SI TU NE CONNAIS PAS VIENS ME VOIR DANS LA CABINE TELEPHONIQUE LA PLUS PROCHE !!!            MESSAGE FROM EIDOLON :JE VOUDRAIS DIRE QUE C EST MIEUX QUE MIEUX ET QUE KRUEGER IL PEUT PAS DIRE LE CONTRAIRE ( ELIAS T EST VIVANT DEPUIS SAMEDI ?)            MESSAGE FROM WEREWOLF :J AIME LES DES SEINS ZA NIMEES ,VIVE MOI !            MESSAGE FROM ILLEGAL LE BAVEUX :HEU TU COMPRENDS J AI TRENTE ANS D ASSEMBLEUR DEVANT MOI ALORS C EST PAS UN SWAPPER DE MERDE QUI VA ME FAIRE CHIER BORDEL!,FUCK!,EIDOLON!!! ( HIHIHIHI! )            MESSAGE FROM KRUEGER :JE SUIS SUR MA BENNE ET J AIME CA ,A DEMAIN LES MECS !            MESSAGE FOR SMILEY : SI TU CONTINUES T AURA UNE TAPETTE !!!            MESSAGE FOR COMPUTER JONES : BON ON A RIEN A TE DIRE SAUF QUE TA MINI ELLE PUE ET TDS IL TE GRUGE AVEC SA RENAULT CINQ TURBO DIESEL  !            MESSAGE FROM ZOOLOOK : CA FAIT DIX ANS QUE JE SUIS SUR MA DEMO MAIS JE CROIS QUE JE VAIS LA RECOMMENCER POUR CHANGER UN PEU ...            BYE ENJOY THIS FANTASTICOULOUS GAME ....SEE YOU LATER !!!!                                          ";
const SCROLL_CHAR_WIDTH = 32; 
const SCROLL_CHAR_HEIGHT = 26;
const SCROLL_SPEED = 8;
const SCROLL_CHARS = " ! #$%&'()*+,-./0123456789:;<=>? ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const NB_FONTS: u8 = (WIDTH/SCROLL_CHAR_WIDTH) + 1;

// palettes
const font_pal = convertU8ArraytoColors(@embedFile("../assets/screens/equinox/fonts_pal.dat"));
const backtop_pal = convertU8ArraytoColors(@embedFile("../assets/screens/equinox/backtop_pal.dat"));
const road_pal = convertU8ArraytoColors(@embedFile("../assets/screens/equinox/road_pal.dat"));
const bob_pal = convertU8ArraytoColors(@embedFile("../assets/screens/equinox/bobs_pal.dat"));

// logo
const backtop_b = @embedFile("../assets/screens/equinox/backtop.raw");
const backscroll_b = @embedFile("../assets/screens/equinox/backscroll.raw");

const road1_b = @embedFile("../assets/screens/equinox/road1.raw");
const road2_b = @embedFile("../assets/screens/equinox/road2.raw");
const logo_b = @embedFile("../assets/screens/equinox/logo.raw");

// bob
const bob_1_b = @embedFile("../assets/screens/equinox/bob1.raw");
const bob_2_b = @embedFile("../assets/screens/equinox/bob2.raw");
const bob_3_b = @embedFile("../assets/screens/equinox/bob3.raw");
const bob_4_b = @embedFile("../assets/screens/equinox/bob4.raw");
const bob_5_b = @embedFile("../assets/screens/equinox/bob5.raw");
const bob_6_b = @embedFile("../assets/screens/equinox/bob6.raw");
const bob_7_b = @embedFile("../assets/screens/equinox/bob7.raw");
const bob_8_b = @embedFile("../assets/screens/equinox/bob8.raw");

const NB_BOBS = 7;
const bobs_images: [NB_BOBS][]const u8 = [_][]const u8{ bob_1_b, bob_8_b, bob_8_b, bob_8_b, bob_8_b, bob_8_b, bob_8_b };

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------

var road_offsets = [18][9]u8{
    [_]u8{ 0, 2, 4, 6, 14, 20, 28, 38, 58},
    [_]u8{ 0, 2, 4, 8, 14, 22, 28, 40, 52},
    [_]u8{ 0, 2, 6, 8, 14, 22, 30, 42, 46},
    [_]u8{ 0, 4, 4, 8, 16, 24, 30, 44, 40},
    [_]u8{ 0, 4, 4, 10, 16, 24, 32, 46, 34},
    [_]u8{ 0, 4, 6, 10, 16, 26, 32, 48, 28},
    [_]u8{ 0, 4, 6, 12, 16, 26, 34, 52, 20},
    [_]u8{ 0, 6, 4, 12, 20, 26, 34, 54, 14},
    [_]u8{ 0, 6, 6, 12, 20, 26, 36, 56, 8},
    [_]u8{ 2, 4, 6, 14, 20, 28, 38, 58, 0},
    [_]u8{ 2, 4, 8, 14, 22, 28, 40, 52, 0},
    [_]u8{ 2, 6, 8, 14, 22, 30, 42, 46, 0},
    [_]u8{ 4, 4, 8, 16, 24, 30, 44, 40, 0},
    [_]u8{ 4, 4, 10, 16, 24, 32, 46, 34, 0},
    [_]u8{ 4, 6, 10, 16, 26, 32, 48, 28, 0},
    [_]u8{ 4, 6, 12, 16, 26, 34, 52, 20, 0},
    [_]u8{ 6, 4, 12, 20, 26, 34, 54, 14, 0},
    [_]u8{ 6, 6, 12, 20, 26, 36, 56, 8, 0},
};

var road_sum = [18][10]u8{
	[_]u8{ 0, 0, 2, 6, 12, 26, 46, 74, 112, 170},
	[_]u8{ 0, 0, 2, 6, 14, 28, 50, 78, 118, 170},
	[_]u8{ 0, 0, 2, 8, 16, 30, 52, 82, 124, 170},
	[_]u8{ 0, 0, 4, 8, 16, 32, 56, 86, 130, 170},
	[_]u8{ 0, 0, 4, 8, 18, 34, 58, 90, 136, 170},
	[_]u8{ 0, 0, 4, 10, 20, 36, 62, 94, 142, 170},
    [_]u8{ 0, 0, 4, 10, 22, 38, 64, 98, 150, 170},
	[_]u8{ 0, 0, 6, 10, 22, 42, 68, 102, 156, 170},
	[_]u8{ 0, 0, 6, 12, 24, 44, 70, 106, 162, 170},
	[_]u8{ 0, 2, 6, 12, 26, 46, 74, 112, 170, 0},
	[_]u8{ 0, 2, 6, 14, 28, 50, 78, 118, 170, 0},
	[_]u8{ 0, 2, 8, 16, 30, 52, 82, 124, 170, 0},
	[_]u8{ 0, 4, 8, 16, 32, 56, 86, 130, 170, 0},
	[_]u8{ 0, 4, 8, 18, 34, 58, 90, 136, 170, 0},
	[_]u8{ 0, 4, 10, 20, 36, 62, 94, 142, 170, 0},
	[_]u8{ 0, 4, 10, 22, 38, 64, 98, 150, 170, 0},
	[_]u8{ 0, 6, 10, 22, 42, 68, 102, 156, 170, 0},
	[_]u8{ 0, 6, 12, 24, 44, 70, 106, 162, 170, 0},
};

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------

pub const Demo = struct {
  
    name: u8 = 0,
    frame_counter: u32 = 0,
    scrolltext: Scrolltext(NB_FONTS) = undefined,
    backtop: Background = undefined,
    backscroll: Background = undefined,
    road1: Sprite = undefined,
    road2: Sprite = undefined,
    logo: Sprite = undefined,
    bobs: Bobs(NB_BOBS) = undefined,
    bobs_pos: [NB_BOBS]f32 = undefined,    
    counter: u8 = 0,

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // first plane
        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.is_enabled = true;
        fb.setPalette(road_pal);
        self.road1.init(fb.getRenderTarget(), road1_b, 320, 85, 0, 112, null, null);
        self.road2.init(fb.getRenderTarget(), road2_b, 320, 85, 0, 112, null, null);
        self.logo.init(fb.getRenderTarget(), logo_b, 203, 23, 160-(203/2), 125, null, null);

        fb = &zigos.lfbs[1];
        fb.is_enabled = true; 
                
        fb.setPalette(backtop_pal);
        fb.setPaletteEntry(5, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
        // fb.setFrameBufferHBLHandler(0, handler_backpal);
        self.backtop.init(fb.getRenderTarget(), backtop_b, 0);        
        self.backscroll.init(fb.getRenderTarget(), backscroll_b, HEIGHT-39);

        fb = &zigos.lfbs[2];
        fb.is_enabled = true; 
        fb.setPalette(bob_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        var i: usize = 0;
        while (i < NB_BOBS) : (i += 1) {
            self.bobs_pos[i] = 0.3*(@intToFloat(f32, i+1));
        }
        self.bobs = Bobs(NB_BOBS).init(fb.getRenderTarget(), bobs_images, 32, 26);

        fb = &zigos.lfbs[3];
        fb.is_enabled = true; 
        fb.setPalette(font_pal);
        fb.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });

        self.scrolltext = Scrolltext(NB_FONTS).init(fb.getRenderTarget(), fonts_b, SCROLL_CHARS, SCROLL_CHAR_WIDTH, SCROLL_CHAR_HEIGHT, SCROLL_TEXT, SCROLL_SPEED, 200-26, null, null, null);

        Console.log("demo init done!", .{});
    }

    pub fn update(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        self.scrolltext.update();
        self.backtop.update();
        self.road1.update(null, null, null, null);

        var i: usize = 0;
        while (i < NB_BOBS) : (i += 1) {

            const x_idx: f32 = 152 + 153 * @sin(self.bobs_pos[i]);
            const y_idx: f32 = 43 + 42 * @cos(self.bobs_pos[i]*1.5);
            const x: i16 = @floatToInt(i16, x_idx);
            const y: i16 = @floatToInt(i16, y_idx);
            self.bobs_pos[i] += 0.04;            

            self.bobs.update(i, x, y);
        }

        _ = zigos;
        _ = elapsed_time;
    }

    pub fn render(self: *Demo, zigos: *ZigOS, elapsed_time: f32) void {

        var fb: *LogicalFB = &zigos.lfbs[0];
        fb.clearFrameBuffer(255);

        self.counter = (self.counter + 1) % 18;
        var i: u8 = 1;
        while(i < 9) : ( i+= 2 ) {
            drawRoad(fb, road1_b, 113, self.counter, i);
        }
        i = 0;
        while(i < 9) : ( i+= 2 ) {
            drawRoad(fb, road2_b, 113, self.counter, i);        
        }

        self.backtop.target.clearFrameBuffer(5);
        self.backtop.render();
        self.backscroll.render();
        
        // self.road1.render();
        // self.logo.render();

        self.bobs.target.clearFrameBuffer(0);
        self.bobs.render();

        fb = &zigos.lfbs[3];
        fb.clearFrameBuffer(0);
        self.scrolltext.render();

        _ = elapsed_time;

    }

    fn drawRoad(fb: *LogicalFB, road: []const u8, pos_y: u16, i: u8, band: u8) void {
        if(road_offsets[i][band] != 0) {
            // road.drawPart(mycanvas, 0, y+road_sum[i][band], 0,road_sum[i][band], 640,road_offsets[i][band], 1.0, 0, 1.0, 1.0);

            // fb dest: (0, y+road_sum[i][band])
            // road src: from (0, road_sum[i][band]) of size 640, road_offsets[i][band]  

            var dst: u16 =  (pos_y + (road_sum[i][band]/2)) * WIDTH;
            var src: u16 = (road_sum[i][band] / 2) * WIDTH;

            var counter: u16 = 0;
            while(counter < WIDTH*(road_offsets[i][band]/2)) : (counter += 1) {
                fb.fb[dst + counter] = road[src + counter];
            }
        }
    }
};
