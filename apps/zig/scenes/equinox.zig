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

const Scrolltext = zg.Scrolltext;
const Background = zg.Background;
const Sprite = zg.Sprite;

const Console = zg.Console;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: u16 = zg.HEIGHT;
const WIDTH: u16 = zg.WIDTH;

// music — the screen's own tune, played by its own 68000 (docs/music/).
// Mad Max's "Cybernoid 2" (1989).
const MUSIC = "cybernoid2.sndh";

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

// The dragons: CODEF wab screen 015 (prototypes/codef/15/screen.js). All seven
// wear the same morph frame, dragon1..dragon8 = bob1..bob8 (halved 64x52).
// Frame 7 is the egg, frame 0 the full dragon.
const NB_DRAGONS = 7;
const DRAGON_W = 32;
const DRAGON_H = 26;
const dragon_frames = [8][]const u8{ bob_1_b, bob_2_b, bob_3_b, bob_4_b, bob_5_b, bob_6_b, bob_7_b, bob_8_b };
const EGG_FRAME = 7;

// screen.js:152-185 — the precalculated trajectory. Each dragon trails the
// previous one by 18 entries; x wraps at 940 and y at 964 (screen.js:303), so
// the two tables drift against each other. Computed on the 640-wide canvas,
// then halved to ST pixels.
const TRAIL = 18;
const X_WRAP = 940;
const Y_WRAP = 964;
const trajectory = blk: {
    @setEvalBranchQuota(20000);
    var xs: [X_WRAP]i16 = undefined;
    var ys: [Y_WRAP]i16 = undefined;
    var fac_x: f64 = 0;
    var fac_y: f64 = 0;
    for (0..Y_WRAP) |i| {
        // the increments, per range of i, exactly as screen.js:157-181
        if (i < 125 or i >= 950) {
            fac_x += 0.05;
            fac_y += 0.05;
        } else if (i < 220) {
            fac_x += 0.03;
            fac_y += 0.035;
        } else if (i < 480) {
            fac_x += 0.06;
            fac_y += 0.03;
        } else if (i < 630) {
            fac_x += 0.045;
            fac_y += 0.035;
        } else {
            fac_x += 0.02;
            fac_y += 0.045;
        }
        const x = 320.0 - 64.0 / 2.0 + ((256.0 - 64.0 / 2.0 - 5.0) * @cos(fac_x));
        const y = 200.0 - 52.0 / 2.0 + 30.0 + ((128.0 - 52.0 / 2.0 - 10.0) * @sin(fac_y));
        if (i < X_WRAP) xs[i] = @intFromFloat(@floor(x / 2.0));
        ys[i] = @intFromFloat(@floor(y / 2.0));
    }
    break :blk .{ .x = xs, .y = ys };
};

// screen.js:146-150 + morphSprite() 216-268. The machine ticks once every
// 10 frames; each state lasts a fixed number of ticks.
const MorphState = enum { in_egg, morphing, alive, demorphing };
const MORPH_TICK = 10;
const SLEEP_TICKS = 60;
const MORPH_TICKS = 20;
const ALIVE_TICKS = 70;
const DEMORPH_TICKS = 20;
const ALIVE_TOP_FRAME = 3; // alive ping-pongs frames 0..3

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
    counter: u8 = 0,
    // the dragons (every field assigned in init(): struct defaults never run)
    frames: u32 = 0, // screen.js `frames`, starts at 1
    tabpos: usize = 0, // trajectory index of the lead dragon for the NEXT frame
    drawn_tabpos: usize = 0, // the index this frame's render draws
    morph_state: MorphState = .in_egg,
    morph_frame: u8 = 0, // screen.js `morphType`
    alive_inc: i8 = 0, // screen.js `aliveInc`
    state_ticks: u32 = 0, // sleepingTime / morphTime / aliveTime / demorphTime

    pub fn init(self: *Demo, zigos: *ZigOS) void {
        Console.log("Demo init", .{});

        // Nothing happens until the user turns sound on — the request just waits.
        zg.requestSong(MUSIC);

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

        // screen.js:60-61, 110-122
        self.frames = 1;
        self.tabpos = 0;
        self.drawn_tabpos = 0;
        self.morph_state = .in_egg;
        self.morph_frame = EGG_FRAME;
        self.alive_inc = 1;
        self.state_ticks = 0;

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

        // screen.js go(): morphSprite(), draw at tabpos, tabpos++, frames++
        if (self.frames % MORPH_TICK == 0) self.tickMorph();
        self.drawn_tabpos = self.tabpos;
        self.tabpos += 1;
        self.frames += 1;

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

        fb = &zigos.lfbs[2];
        fb.clearFrameBuffer(0);
        self.drawDragons(fb);

        fb = &zigos.lfbs[3];
        fb.clearFrameBuffer(0);
        self.scrolltext.render();

        _ = elapsed_time;

    }

    // morphSprite(), screen.js:216-268: egg (frame 7) for 60 ticks, hatch
    // 7 -> 0 over 20 ticks, ping-pong 0..3 for 70 ticks, back to 7 over 20.
    fn tickMorph(self: *Demo) void {
        self.state_ticks += 1;
        switch (self.morph_state) {
            .in_egg => {
                self.morph_frame = EGG_FRAME;
                if (self.state_ticks == SLEEP_TICKS) self.enter(.morphing);
            },
            .morphing => {
                if (self.morph_frame > 0) self.morph_frame -= 1;
                if (self.state_ticks == MORPH_TICKS) self.enter(.alive);
            },
            .alive => {
                if (self.morph_frame == 0) self.alive_inc = 1 else if (self.morph_frame == ALIVE_TOP_FRAME) self.alive_inc = -1;
                self.morph_frame = @intCast(@as(i8, @intCast(self.morph_frame)) + self.alive_inc);
                if (self.state_ticks == ALIVE_TICKS) self.enter(.demorphing);
            },
            .demorphing => {
                if (self.morph_frame < EGG_FRAME) self.morph_frame += 1;
                if (self.state_ticks == DEMORPH_TICKS) self.enter(.in_egg);
            },
        }
    }

    fn enter(self: *Demo, state: MorphState) void {
        self.morph_state = state;
        self.state_ticks = 0;
    }

    // screen.js:301-304: seven dragons, one morph frame, 18 trajectory entries apart
    fn drawDragons(self: *Demo, fb: *LogicalFB) void {
        const dst = zg.blit.Dst.plane(fb);
        const img = zg.blit.Image.init(dragon_frames[self.morph_frame], DRAGON_W);
        for (0..NB_DRAGONS) |n| {
            const idx = self.drawn_tabpos + n * TRAIL;
            zg.blit.blit(dst, img, null, trajectory.x[idx % X_WRAP], trajectory.y[idx % Y_WRAP], 0, .copy);
        }
    }

    fn drawRoad(fb: *LogicalFB, road: []const u8, pos_y: u16, i: u8, band: u8) void {
        if(road_offsets[i][band] != 0) {
            // road.drawPart(mycanvas, 0, y+road_sum[i][band], 0,road_sum[i][band], 640,road_offsets[i][band], 1.0, 0, 1.0, 1.0);

            // fb dest: (0, y+road_sum[i][band])
            // road src: from (0, road_sum[i][band]) of size 640, road_offsets[i][band]  

            const dst: u16 =  (pos_y + (road_sum[i][band]/2)) * WIDTH;
            const src: u16 = (road_sum[i][band] / 2) * WIDTH;

            var counter: u16 = 0;
            while(counter < WIDTH*(road_offsets[i][band]/2)) : (counter += 1) {
                fb.fb[dst + counter] = road[src + counter];
            }
        }
    }
};
