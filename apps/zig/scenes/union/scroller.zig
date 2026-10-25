// --------------------------------------------------------------------------
// Union main — the boring-but-oldschool bottom SCROLLTEXT (efmain.js). On plane
// 1, below the actors, with its own palette from the split (p1_split.zig). Faithful to efmain.js/codef_scrolltext.js/codef_fx_optim.js:
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
const LogicalFB = zg.LogicalFB;

const st2 = zg.scrolltext2;
const ss = @import("scroll_strip.zig"); // the strip and the wave, by the CPU
const wave_sin = @import("wave_sin.zig");
const emu = @import("f32emu.zig");

// A phase moved by less than 2 pi back into [0, 2 pi).
fn wrap(r: i64) i64 {
    if (r < 0) return r + emu.TWO_PI;
    if (r >= emu.TWO_PI) return r - emu.TWO_PI;
    return r;
}

const NUM_SLOTS: usize = 14;
const GLYPH: u16 = 32;
const STRIP_W: u16 = 400; // == PHYSICAL_WIDTH; the strip spans the full plane
const STRIP_H: u16 = 32;
const BASE_Y: i16 = 217; // Codef scrollraster canvas y=424 -> plane y (half)
const WAVE_AMP: i32 = 10; // half of orig 20
const WAVE_COL: u16 = 3; // half of orig 6px column step
const WAVE_INC: i64 = @intCast(emu.of(0.03)); // per-column phase step (unchanged), f32emu units
const WAVE_DRIFT: i64 = -WAVE_INC; // per-frame phase drift (unchanged)
pub const BAND_TOP: i32 = BASE_Y - 10; // BASE_Y - WAVE_AMP
pub const BAND_ROWS: i32 = 20 + STRIP_H + 1; // the wave's swing, the strip, and a row for the rounding
const SCROLL_SPEED: i32 = 3; // half of EFMAIN_SCROLL_SPEED=6

const fontsin_bits = @embedFile("../../assets/screens/union_main/fontsin.bits");
const rasters = @embedFile("../../assets/screens/union_main/rasters.raw");

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

const ScrollerFx = st2.Scroller(NUM_SLOTS);

pub const Scroller = struct {
    fx: ScrollerFx = .{},
    // The f32 phase, kept by f32emu.zig (signed), and the same phase mod 2 pi, moved by the
    // exact amount the phase moves (integers since 2026-10-25: no float a frame on ZIGGY).
    wave_v: i64 = 0,
    wave_r: i64 = 0,

    pub fn init(self: *Scroller, zigos: *ZigOS) void {
        // the text is drawn on P1, in p2.pal's colours (p1_split.zig)
        ss.init(&zigos.lfbs[3]); // the flat strip, before the wave bends it: plane 3, never enabled
        self.wave_v = 0;
        self.wave_r = 0;
        self.fx.init(.{
            .glyph_w = GLYPH,
            .glyph_h = GLYPH,
            .cols = 10,
            .ascii_base = 32,
            .font_out_sheet_w = 320,
            .font_out = &ss.CLASS, // scrolltext2 only scrolls the slots here; ss draws them
            .font_in_bits = fontsin_bits,
            .raster = rasters,
            .raster_w = 384,
            .raster_h = 32,
        }, SCROLL_TEXT, SCROLL_SPEED);
    }

    pub fn update(self: *Scroller) void {
        self.fx.update();
    }

    /// Over P1, last: the band rows BAND_TOP .. BAND_TOP + BAND_ROWS - 1 are written whole
    /// (the text where the wave puts it, 0 elsewhere), so nobody erases them.
    pub fn draw(self: *Scroller, zigos: *ZigOS) void {
        ss.draw(&zigos.lfbs[3], &self.fx);
        // FX.siny(0,20,6): column groups of WAVE_COL px, each offset vertically by
        // sin(phase)*amp; the phase advances per group during the sweep but the persisted
        // state only carries the per-frame drift (Codef's oldvalue+offset reset after the loop).
        // zg.wave.SineSum's .accumulate sweep (amp WAVE_AMP, phase wave_v, inc WAVE_INC,
        // .round): the phases the f32 sums took, each rounded sine by wave_sin.zig.
        var p = self.wave_v;
        var r = self.wave_r;
        var top: [GROUPS]i32 = undefined; // band row of text row 0, per group
        for (&top) |*t| {
            t.* = @as(i32, BASE_Y) + wave_sin.rounded(emu.turns(r)) - BAND_TOP;
            const next = emu.sadd(p, WAVE_INC);
            r = wrap(r + (next - p));
            p = next;
        }
        const v = emu.sadd(self.wave_v, WAVE_DRIFT);
        self.wave_r = wrap(self.wave_r + (v - self.wave_v));
        self.wave_v = v;
        ss.wave(&zigos.lfbs[1], &zigos.lfbs[3], @intCast(BAND_TOP), @intCast(BAND_ROWS), &top, WAVE_COL);
    }
};

const GROUPS = (STRIP_W + WAVE_COL - 1) / WAVE_COL; // 134 column groups
comptime {
    if (WAVE_AMP != wave_sin.AMP) @compileError("wave_sin rounds another amplitude");
    if (STRIP_W != ss.W or 2 * (BASE_Y - BAND_TOP) != ss.PAD or BAND_ROWS != ss.PAD + STRIP_H + 1) @compileError("scroll_strip's geometry");
}
