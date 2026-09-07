// --------------------------------------------------------------------------
// Union main — the boring-but-oldschool bottom SCROLLTEXT (efmain.js). Plane 2
// (P2), fullscreen. Faithful to efmain.js/codef_scrolltext.js/codef_fx_optim.js:
//   - EFMAIN_SCROLL_SPEED=6 orig -> 3 px/frame half; glyph pitch 64 -> 32 half.
//   - ^P<digit>/^S<digit> control codes: pause 60*digit frames / set speed.
//   - FX.siny(0,20,6): the flat strip is displaced vertically per 3px column
//     (half of orig 6px), half amp 10, phase += 0.03/column, drifts -0.03/frame
//     (so the wave crawls right over time) - see scrolltext2.zig's Scroller for
//     the glyph feed/recycle state machine (shared, generic) and `zigos/effects/
//     scrolltext2.zig` docs for the exact algorithm this mirrors.
//
// scrolltext2.zig is intentionally zigos-free (stride-agnostic, reusable), so
// it's reached here by relative path rather than through the "zigos" module.
// --------------------------------------------------------------------------
const std = @import("std");
const zg = @import("zigos");
const ZigOS = zg.ZigOS;
const Color = zg.Color;
const LogicalFB = zg.LogicalFB;
const convertU8ArraytoColors = zg.convertU8ArraytoColors;

const st2 = zg.scrolltext2;

const NUM_SLOTS: usize = 14;
const GLYPH: u16 = 32;
const STRIP_W: u16 = 400; // == PHYSICAL_WIDTH; the strip spans the full plane
const STRIP_H: u16 = 32;
const BASE_Y: i16 = 217; // Codef scrollraster canvas y=424 -> plane y (half)
const WAVE_AMP: f32 = 10.0; // half of orig 20
const WAVE_COL: i16 = 3; // half of orig 6px column step
const WAVE_INC: f32 = 0.03; // per-column phase step (unchanged, unitless)
const WAVE_DRIFT: f32 = -0.03; // per-frame phase drift (unchanged)
const SCROLL_SPEED: i32 = 3; // half of EFMAIN_SCROLL_SPEED=6

const fontsout = @embedFile("../../assets/screens/union_main/fontsout.raw");
const fontsin_bits = @embedFile("../../assets/screens/union_main/fontsin.bits");
const rasters = @embedFile("../../assets/screens/union_main/rasters.raw");
const p2_pal = convertU8ArraytoColors(@embedFile("../../assets/screens/union_main/p2.pal"));

// The scrolltext verbatim (efmain.js this.efmain_text, all 5 authors' greetz
// concatenated exactly as in the original source, including its ^P/^S codes).
const SCROLL_TEXT =
    // 13 leading spaces (was 5): scrolltext2 primes all NUM_SLOTS across the
    // visible strip at init, so the text must start with a full strip of blanks
    // to enter cleanly from the right edge instead of appearing mid-screen.
    "             TRSI AND WAB ARE PROUD TO PRESENT YOU THE UNION DEMO C^P2RACKED, HACKED, DEPACKED, RIPPED, DISASSEMBLED THEN RECODED BY US IN 2013 FOR YOUR PLEASURE !!!!!!! THIS REMAKE IS MADE USING CODEF AND MELONJS FOR THE JAVASCRIPT PARTS, THANK TO NONAMENO (CODEF) AND EVILO (MELONJS) FOR GIVING US THE MOTIVATION TO CODE SOME STUFF, WE'RE GETTING OLD AND LAZY !!!!   FOR THE CREDITS, PLEASE READ THE BANNERS, SO LET'S USE THIS BORING BUT SO OLDSCHOOL SCROLLTEXT TO GREET ALL THE PLANET......  2013 GREETINGS GO TO :     WAB      ^P1(NONAMENO, TOTORMAN), ALL THE FACEBOOK CODEF GROUP MEMBERS (NEWCORE, SOLO, AYOROS, JACE, GUNSTICK, ...),    TRSI     ^P1(71M, AYATOLLAH, WARHEAD, MIKE, H20, STREETUFF, SPOTTER, SANTA, DIGIMAN, IRATA, COOLCAT, REBB, WODK,... GUYS I MISS YOU SO MUCH),   MJJ PROD   ^P1(FEL'X, WILFRIED, STRIDER, C-REM, MR NOURS, TOBE, TOOSEB, VEVER, GLOKY, TOUFOU, BIGFOOT, FLOOPY... ),.    SHAZZ'S ALL TIME GREETINGS GO TO : HEMOROIDS   ^P1(HI SINK ! ALWAYS NICE TO TALK WITH YOU OF THE OLD FIGHTS), TSUNOO RHILTY FROM TROLL AND CO (HEY FRED !),     BOS      ^P1(SALUT DAHAN), ST KNIGHTS (ALDYN, JACE), CHECKPOINT (HALLO 505 UND DEFJAM), UNLIMITED MATRIX (GUNSTICK UBER CODER), DUNE (SPECIAL HI TO CHUCK, CORBEAU AND MIC), SECTOR ONE (ST GHOST, ZERKMAN, FROST), EQUINOX (HI KEOPS !), DEAD HACKERS SOCIETY (HEY GIZMO ! EVIL !), LINEOUT, RESERVOIR GODS (HELLO DAMO), CONDENSE (NORECESS MY MASTER !), THE REPLICANTS (SALUT ILLEGAL !), OVERLANDERS (HEY BEN !), OXYGENE (SALUT ARNAUD), ST SURVIVOR, FMC CONNECTION (HI KRYSTAL), THE CAREBEARS, THE EXCEPTIONS, LEGACY, TNS, ST CONNEXION, ELITE (MARCER), SYNC (HI TROED), SCSI, FIT, ADRENALINE, PARADOX (HI PARANOID), D-BUG........   NOW A VERY SPECIAL AND VERY WARM HI TO SOME AWESOME CONSOLE SCENES :   THE PS2 SCENE AND ESPECIALLY THE FROGGIES ^P2(NIPPY MY BEST FRIEND, TMATOR, DINGOFR, EVILO,... ) AND ALL THE PS2 SCENE I REALLY LOVE (PS2DEV GUYS : RAIZOR, EMOON/TBL, KRABOB/MANKIND, PIXEL,....), FOREVER THER PS2 WILL STAY IN MY HEART AS THE BEST CONSOLE TO CODE ON.... AND GUYS.... NO WORDS TO DESCRIBE ! .....  TO ALL THE PSP SCENE (PARADISE, TBL, SEB...) ...... TO ALL THE DREAMCAST SCENE (WHAT A GREAT CONSOLE !!!!), ALL THE C64 SCENE AND ESPECIALLY THE DTV MANIACS), THE SMALL BUT TALENTED THOMSON SCENE.... DAMN I PLAYED ON SO MANY PLATFORMS.... AND MY SPECIAL THOUGHTS GO TO TITAN AND MY GOOD FRIENDS THERE : IROKOS, ALIEN, KENET, GENCHA, YOU'RE GREAT GUYS !  RA, THE UNIQUE RA ! ........  AND ALL THE OLD FARTS I FORGOT.......... " ++
    "TOTORMAN'S GREETINGS ARE GOING TO : SHAZZ OF COURSE, FOR LETTING ME PARTICIPATE INTO THIS GREAT REMAKE, NONAMENO FOR CODEF AND MORAL SUPPORT :), ALL THE CODEF AND WAB USERS, FOLLOWERS, FACEBOOK FANS, THE OLD AMIGA SCENE FOR GIVING US MANY REMAKES TO DO, THE OLD ATARI SCENE FOR MAKING THE AMIGA SCENE BETTER (LOL), C.CORTI FOR THE SO MANY TIMES USED JAVASCRIPT MODULEPLAYER, AND ALL THE FRIENDS I MAY FORGOT !!!   ...    " ++
    "MELLOWMAN GREETINGZ GO TO : (IN NO PARTICULAR ORDER OF IMPORTANCE...)   -NONAMENO-  (THANKS FOR YOUR HELP, AND INSPIRATION TO MAKE SCREEN LIKE THESE!)   -SHAZZ-  (THANKS FOR YOUR SUPPORT WHEN WRITING THESE SCREENS - A PLEASURE TO WORK WITH YOU!)   -TOTORMAN-  (GREAT GUY TO KNOW, ALWAYS WILLING TO HELP AND OFFER GUIDANCE!)   -NEWCORE-  (THANKS SO MUCH FOR ALL YOUR HELP ON VARIOUS THINGS, ESPECIALLY WITH MY REMAKE OF THE SWEDISH NEW YEAR DEMO!)   -ZORRO2/NOEXTRA-  (HOPE THAT YOU ARE FULLY RECOVERED AFTER YOUR RECENT STAY IN HOSPITAL!)   -THE ADMINISTRATOR-  (YOU NEED TO GET WITH THE CODEF MAN!)   -JOHN MINDFUL-  (THANKS FOR ASSISTANCE WITH TESTING AND ADVICE OF THE LAST FEW MONTHS!)   -SHEEPDIP2000-  (KEEP PLUGGING AWAY!)   PLUS ALL OF THE OTHER USUAL SUSPECTS.... -GANDALF-   -ZUUL-   -FLUTTERSHY-   -JANNE HAMALAINEN-   -SPEEDSTAR-   -NEXUS-   AND OF COURSE MOST IMPORTANTLY...... -THE MEMBERS OF THE UNION-  (THANKS GUYS, FOR THE DEMO OF THE 1990S FOR THE ATARI ST!!)     " ++
    "NOW SOME PERSONAL MESSAGES......... SHAZZ ON THE KEYBOARD, I'M SURE MANY PEOPLE WILL COMPLAIN THAT THERE IS NOTHING ORIGINAL AND DIFFICULT TO PORT OLD EIGHTIES DEMO IN 2013 AND THEY ARE RIGHT, BUT PERSONALLY IT WAS MORE A TRIBUTE AND A CHALLENGE TO ACCEPT AND... I DON'T REALLY CARE OF THOSE COMMENTS, I HAD FUN, ENOUGH FOR ME ! BY THE WAY, I MAY LOOK DUMB BUT I LEARNT A LOT WHILE TRYING TO REDO THOSE OLD EFFECTS, I HAD TO DO SOME REVERSE ENGINEERING AND FOUND THE TRICKS USED, AND I THOUGHT I KNEW MOST OF THEM.... BUT NO ! I DISCOVERED SOME NEW ONES...... AND AT THE END IF THE 3RD SCREEN OF TCB IS STILL IN ANY ST DEMOCODER MEMORY, THAT'S DEFINITIVELY THE MOST TRICK SCREEN TO PORT, EVEN IF THE PARALLAX IS FAKED, THE 3D SCROLLER IS STILL AMAZING !!!!! I STILL WONDER HOW IT WAS DONE.... BY THE WAY, I HAD SOME FUN TIME WITH TOTORMAN AFTER A FIRST NEAR COMPLETE VERSION OF THIS INTRO TO TRY TO OPTIMIZE IT IN ORDER TO RUN SMOOTHLY ON ANY COMPUTER OR TABLET, IT WAS NOT LIKE REORDERING 68000 INSTRUCTIONS TO OPTIMIZE THE PIPELINE USAGE OR WRITING SOME UGLY AUTOGENERATED CODE BUT THAT WAS INTERESTING TO SEE HOW TO USE THE BROWSER JAVASCRIPT ENGINE TO ACHIEVE THE BEST FRAMERATES, AND IT IS NOT STRAIGHT FORWARD..... FOR THAT'S ALL, HOPE YOU HAVE FUN !!!!    " ++
    ".....AND HERE WE GO! MELLOWMAN HERE ON THE KEYS, AND LET ME SAY HOW SPECIAL IT IS TO BE PART OF THIS UNION DEMO CODEF REMAKE! PARTICULARLY BECAUSE IT WAS THE FIRST MULTI-SCREEN DEMO I EVER SAW ON THE ATARI ST.... UP UNTIL THEN, I'D ONLY SEEN DEMO'S LIKE THE B.I.G. DEMO, AND SOME OF THE TCB INTROS, AND THE UNION DEMO BLEW ME AWAY! EVEN AS MORE OF THESE MULTI-SCREEN DEMO'S APPEARED.... THE UNION DEMO WAS ALWAYS MY FAVOURITE.... ESPECIALLY ONE PARTICULAR SCREEN.... THE LEVEL 16 FULLSCREEN! ALTHOUGH THE FULLSCREEN WAS COOL, THAT WASN'T THE REASON WHY I LOVED IT SO MUCH... IT WAS BECAUSE OF THAT SIMPLE MELODY THAT ACCOMPANIED THE SCREEN, I NEVER FORGOT IT..... WHICH WAS WHY WHEN I FIRST STARTED TO MAKE CODEF SCREENS, I REALLY WANTED TO REMAKE THE LEVEL 16 SCREEN, JUST SO I COULD ENJOY THAT MUSIC AGAIN.... AND OBVIOUSLY THIS LED ME TO WORK WITH SHAZZ ON THE REMAKE, AND THAT LED TO WHERE WE ARE TODAY, GETTING READY TO ENJOY THIS GREAT DEMO, ALL OVER AGAIN!!  NOW I WAS TEMPTED TO DO SOME MASSIVE OVERBLOWN LONG SCROLLTEXT LIKE WE OFTEN USED TO SEE BACK IN THE DAY.... BUT THESE DAYS IT'S ALL TOO EASY FOR YOU TO CLICK SOMEWHERE ON YOUR BROWSER AND GOTO A DIFFERENT PAGE, WHEREAS BACK IN THE OLD DAYS, YOU HAD TO WAIT FOR THE DISK TO LOAD !!! .....WELL I THINK I'VE USED ABOUT ALL THE SPACE SHAZZ WILL ALLOW ME, IF NOT MORE, SO I'D BETTER LEAVE YOU GUYS IN PEACE... UNTIL WE SEE YOU AGAIN, TAKE CARE..... AND REMEMBER TO CHECK OUT MY OTHER CODEF SCREENS WHICH CAN BE SEEN AT CODEF.NAMWOLLEM.CO.UK !! LATERZ......    " ++
    "BEFORE WRAPPING (OR NOT] THIS SCROLLER, SOME DETAILS ON THIS INTRO, THE CHIPTUNES YOU'RE LISTENING TO ARE : '150 MPH' AND 'ANDROIDS' BY TAO/ACF, 'DROOLING' BY 505/CHECKPOINT, 'BMT SCREEN' BY LAP/NEXT, 'REALITY' BY BIG ALEC/DF AND OF COURSE 'SHARPNESS BUZZTONE' BY JESS/OVR. THE GAME LIKE IS A RIP OF THE SO COOL 20TH ANNIVERSARY MEGADEMO ORGANIZED BY DHS, ALL GFX DONE BY C-REM/MJJ PROD..... SPECIAL DEDIDACE A CHUCK/DUNE, LA DRAGONBALL C'EST POUR TOI !!!!  ...........  OH I FORGOT THE TYPICAL SPEECH ON WHO WE ARE, BUT IS IT STILL NECESSARY TO PRESENT TRSI IN 2013 ???? I HOPE NO.... SO ENOUGH CRAP FOR TODAY, LET'S WRAP...............";

// The scrolltext spans the full 400-wide plane (STRIP_W), spilling into the
// side borders, so they must stay open for every line — flicker at
// OVERSCAN_MAGIC_X (see docs/HW_API.md "Opening the borders").
fn handlerOverscan(fb: *LogicalFB, zigos: *ZigOS, line: u16, col: u16) void {
    _ = zigos;
    _ = line;
    _ = col;
    fb.flickerBorder();
}

const ScrollerFx = st2.Scroller(NUM_SLOTS);

pub const Scroller = struct {
    fx: ScrollerFx = .{},
    strip: [STRIP_H][STRIP_W]u8 = undefined,
    wave_v: f32 = 0,

    pub fn init(self: *Scroller, zigos: *ZigOS) void {
        const p2: *LogicalFB = &zigos.lfbs[2];
        p2.is_enabled = true;
        p2.setOverscanBuffer();
        p2.setFrameBufferHBLHandler(zg.OVERSCAN_MAGIC_X, handlerOverscan);
        p2.setPalette(p2_pal);
        p2.setPaletteEntry(0, Color{ .r = 0, .g = 0, .b = 0, .a = 0 }); // transparent

        self.wave_v = 0;
        self.fx.init(.{
            .glyph_w = GLYPH,
            .glyph_h = GLYPH,
            .cols = 10,
            .ascii_base = 32,
            .font_out_sheet_w = 320,
            .font_out = fontsout,
            .font_in_bits = fontsin_bits,
            .raster = rasters,
            .raster_w = 384,
            .raster_h = 32,
        }, SCROLL_TEXT, SCROLL_SPEED);
    }

    pub fn update(self: *Scroller) void {
        self.fx.update();
    }

    pub fn draw(self: *Scroller, zigos: *ZigOS) void {
        const p2: *LogicalFB = &zigos.lfbs[2];
        p2.clearFrameBuffer(0);

        for (&self.strip) |*row| @memset(row, 0);
        self.fx.draw(@as([*]u8, @ptrCast(&self.strip))[0 .. STRIP_H * STRIP_W], STRIP_W, STRIP_W);

        compositeSiny(p2, &self.strip, &self.wave_v);
    }
};

// FX.siny(0,20,6): copy the strip column-by-column (WAVE_COL wide) into the
// plane, each column group offset vertically by sin(phase)*amp; phase advances
// per column during the sweep but the *persisted* state only carries the
// per-frame drift (mirrors Codef's oldvalue+offset reset after the loop).
fn compositeSiny(p2: *LogicalFB, strip: *const [STRIP_H][STRIP_W]u8, wave_v: *f32) void {
    const pw: i16 = @intCast(p2.fb_w);
    const ph: i16 = @intCast(p2.fb_h);
    var v: f32 = wave_v.*;
    var x: i16 = 0;
    while (x < STRIP_W) : (x += WAVE_COL) {
        const y_off: i16 = @intFromFloat(@round(@sin(v) * WAVE_AMP));
        const dst_y0 = BASE_Y + y_off;
        var cx: i16 = 0;
        while (cx < WAVE_COL and x + cx < STRIP_W) : (cx += 1) {
            const px = x + cx;
            if (px < 0 or px >= pw) continue;
            var ry: u16 = 0;
            while (ry < STRIP_H) : (ry += 1) {
                const py = dst_y0 + @as(i16, @intCast(ry));
                if (py < 0 or py >= ph) continue;
                const pixel = strip[ry][@intCast(px)];
                if (pixel == 0) continue;
                p2.fb[@as(usize, @intCast(py)) * p2.stride + @as(usize, @intCast(px))] = pixel;
            }
        }
        v += WAVE_INC;
    }
    wave_v.* += WAVE_DRIFT;
}
