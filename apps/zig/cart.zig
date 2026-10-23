// --------------------------------------------------------------------------
// Build-time cart selector. Rooted in apps/zig/ (NOT in scenes/) so a scene's
// @embedFile("../assets/…") and relative imports resolve inside this module's
// package. build.zig passes the scene index via the `cart_opts` module; because
// the index is comptime, only the selected scene is compiled into this cart.
//
// The switch order MUST match the cart_names list in build.zig and the tags in
// apps/zig/scenes/catalog.zig.
// --------------------------------------------------------------------------
const opts = @import("cart_opts");

const scene = switch (opts.index) {
    0 => @import("scenes/menu.zig"), // the launcher (demo.wasm)
    1 => @import("scenes/union_intro.zig"),
    // 2: union_main, excluded in build.zig (union/doors.zig runs inside union_intro).
    3 => @import("scenes/music_debug.zig"),
    4 => @import("scenes/blitter_demo.zig"),
    5 => @import("scenes/scroll_demo.zig"),
    6 => @import("scenes/obj_demo.zig"),
    7 => @import("scenes/gem_desktop.zig"),
    8 => @import("scenes/st_replay.zig"),
    9 => @import("scenes/ancool.zig"),
    10 => @import("scenes/bladerunners.zig"),
    11 => @import("scenes/dbug.zig"),
    12 => @import("scenes/deltaforce.zig"),
    13 => @import("scenes/deltaforce2.zig"),
    14 => @import("scenes/empire.zig"),
    15 => @import("scenes/equinox.zig"),
    16 => @import("scenes/fallen_angels.zig"),
    17 => @import("scenes/fullscreen.zig"),
    18 => @import("scenes/ics.zig"),
    19 => @import("scenes/leonard.zig"),
    20 => @import("scenes/maxi.zig"),
    21 => @import("scenes/medium_overscan.zig"),
    22 => @import("scenes/res_switch.zig"),
    23 => @import("scenes/shapes_tester.zig"),
    24 => @import("scenes/stcs.zig"),
    25 => @import("scenes/tex.zig"),
    26 => @import("scenes/badflicker.zig"),
    27 => @import("scenes/stream.zig"),
    28 => @import("scenes/noextra.zig"),
    29 => @import("scenes/replicants_dd2.zig"),
    30 => @import("scenes/supplex_fs2.zig"),
    31 => @import("scenes/replicants_garfield.zig"),
    32 => @import("scenes/ulm_spoon_distorter.zig"),
    33 => @import("scenes/replicants.zig"), // REPS OLD — pre-CODEF-port Replicants, kept for comparison
    34 => @import("scenes/cuddly_starwars.zig"),
    35 => @import("scenes/replicants_kickoff2.zig"),
    36 => @import("scenes/dyno_paradis3.zig"),
    37 => @import("scenes/mandelbrot.zig"),
    38 => @import("scenes/stniccc.zig"),
    39 => @import("scenes/tex_neoshow.zig"),
    40 => @import("scenes/elite_snooker.zig"),
    41 => @import("scenes/union_demo.zig"),
    42 => @import("scenes/tutorial.zig"), // docs/TUTORIAL.md: your first screen
    43 => @import("scenes/mpp_truecolor.zig"), // more than 256 colours: per-line palettes (MPP)
    44 => @import("scenes/union_multifake.zig"),
    45 => @import("scenes/union_textracker.zig"),
    // 46: union_intro_screen, excluded in build.zig (its splash opens union_demo now).
    47 => @import("scenes/union_deltaforce.zig"),
    48 => @import("scenes/union_texcopier.zig"),
    49 => @import("scenes/union_tnt3.zig"),
    50 => @import("scenes/union_l16.zig"),
    51 => @import("scenes/union_tnt1.zig"),
    52 => @import("scenes/union_reps.zig"),
    53 => @import("scenes/union_tnt2.zig"),
    54 => @import("scenes/union_beatdis.zig"),
    55 => @import("scenes/union_superscroller.zig"),
    56 => @import("scenes/tutorial_steps.zig"), // docs/TUTORIAL.html runs this per step
    57 => @import("scenes/automation442.zig"),
    58 => @import("scenes/big_demo.zig"), // The Exceptions / The B.I.G. Demo (CODEF screen 23)
    59 => @import("scenes/tlb_spoon.zig"), // The Lost Boys / The Twiddle Demo (CODEF screen 122)
    60 => @import("scenes/tcb_colorshock.zig"), // The Carebears / Colorshock 2 (CODEF screen 172)
    61 => @import("scenes/vex.zig"), // vEctRoniX / VEX 2025 GTA VI cracktro (original ST binary)
    62 => @import("scenes/replicants_emlyn.zig"), // The Replicants / Emlyn Hughes (CODEF screen 17)
    63 => @import("scenes/scrolllab.zig"), // scrolltext distortion lab (codef_fx filters)
    64 => @import("scenes/tsl_hybridglenz.zig"), // The Silents / Hybrid Glenz (CODEF screen 417)
    65 => @import("scenes/polkadots.zig"), // POLKA DOTS: the halftone torus (CODEF screen 81)
    66 => @import("scenes/elite_cfsr.zig"), // ELITE / Challenge Foot Senior cracktro (original ST binary)
    67 => @import("scenes/rno_sodium.zig"), // RNO / SODIUM intro (original ST binary)
    68 => @import("scenes/rno_natrium.zig"), // RNO / NATRIUM 96k intro (original ST binary)
    69 => @import("scenes/dhs_0pxl0reg.zig"), // DHS / (n)0 PIXELS (n)0 REGRETS (original ST binary)
    70 => @import("scenes/trsi_transarctica.zig"), // TRSI / TRANSARCTICA cracktro (original Falcon030 binary)
    71 => @import("scenes/north_south.zig"), // Infogrames / NORTH & SOUTH, the battle (original ST program, playable)
    72 => @import("scenes/joust.zig"), // JOUST, Atari Corp 1986: the game (original ST binary, playable)
    73 => @import("scenes/tcb_spreadpoint.zig"), // The Carebears / The Spreadpoint Demo (CODEF screen 469)
    74 => @import("scenes/stcs_css3.zig"), // STCS / Tsunoo Rhilty 3rd CSS Convention intro (original ST binary)
    75 => @import("scenes/tcb_weirddream.zig"), // TCB + REPLICANTS / WEIRD DREAM crack intro (CODEF screen 345)
    76 => @import("scenes/swedish_newyear.zig"), // Swedish New Year Demo, menu + 5 screens (CODEF screen 295)
    77 => @import("scenes/gen4_3615.zig"), // ULM / 3615 GEN4, The Fate (CODEF screen 539)
    78 => @import("scenes/rick_dangerous.zig"), // RICK DANGEROUS, Core Design / Firebird 1989: the game (original ST binary, playable)
    79 => @import("scenes/skystrike.zig"), // SKYSTRIKE, Shadow Software 1990: the STOS game (Automation Menu Disk 258, playable)
    80 => @import("scenes/ulm_dsots.zig"), // ULM, The Dark Side of the Spoon: the main menu (its door launches the Parallax Distorter)
    81 => @import("scenes/snyd_90.zig"), // OMEGA / SYNC / TCB, Swedish New Year Demo 89-90 (original disk)
    82 => @import("scenes/dune_gen4.zig"), // DUNE / GEN4 DEMO 1990 (original ST disk): intro, main part, title, menu, F1, F2
    83 => @import("scenes/naos_nitrowave.zig"), // NAOS / THE NITROWAVE DEMO, menu + F1 + F2 + F3 (ported from the ST disk)
    84 => @import("scenes/raytrace.zig"), // SDF ray tracer, Q16.16 fixed point (FPGA CPU benchmark)
    85 => @import("scenes/raytrace_f32.zig"), // the same ray tracer on f32
    86 => @import("scenes/sap_test.zig"), // SAP TEST: Atari 8-bit SAP tunes on the POKEY, a jukebox
    87 => @import("scenes/fuji_hobbytronic.zig"), // FUJI HOBBYTRONIC: a 3D Fuji with rasters, to an ASMA SAP tune on the POKEY
    88 => @import("scenes/replicants_emlyn_f32.zig"), // Emlyn Hughes on the CODEF algorithm in f32 (62 is fixed point)
    89 => @import("scenes/polkadots_f32.zig"), // POLKA DOTS on the CODEF algorithm in f32 (65 is fixed point)
    90 => @import("scenes/xm_test.zig"), // XM TEST: one text plane, keys 1-3 play an XM (8 / 12 channels / local), 4 stops
    91 => @import("scenes/sysinfo.zig"), // SYSINFO: what the machine reports about itself, after HWAM's SysInfo 8.34
    92 => @import("scenes/lockbuster2.zig"), // LOCKBUSTER 2, "for DMA": the intro's six planar scroll engines (ported from the Go re-creation of the ST binary)
    93 => @import("scenes/kickoff2.zig"), // KICK OFF 2, the friendly: the Go re-creation's 16.16 soccer engine on the 320x200 plane
    94 => @import("scenes/grodan_kvack.zig"), // GRODAN & KVACK KVACK, The Carebears 1989: the six-layer scroll demo (ported from the Go re-creation)
    95 => @import("scenes/larcociel5.zig"), // DMA INTRO 5 "LARCOCIEL", DMA 1990: the ribbon trail + perspective glyph raster + YM-volume Batmen (ported from the Go re-creation)
    96 => @import("scenes/larcociel2.zig"), // DMA INTRO 2 "LARCOCIEL", DMA 1990: the animated background band + projected ball trail + slice-stream scrolltext (ported from the Go re-creation)
    97 => @import("scenes/bubblebobble.zig"), // BUBBLE BOBBLE, Taito 1986: the Go remake's 25-round campaign, six enemy kinds, elements and the level editor, with the original YM tunes on the machine's own chip
    98 => @import("scenes/chonchon.zig"), // CHONCHON (a Chon-Chon / DMA intro): the native motion's stars, ring scrollers and warped chrome logo, the YM-volume meters and the per-line raster (ported from the Go re-creation)
    99 => @import("scenes/ikplus.zig"), // THE REPLICANTS / "INTERNATIONAL KARATE PLUS" (IK+) cracktro: four-size scrolltext, logo, stars, two real per-scanline rasters (ported from the Go re-creation)
    100 => @import("scenes/chonchon2.zig"), // CHONCHON 2: sliding DMA panels, two animated sprite paths, ribbon, music meters and per-line raster (ported from the Go re-creation)
    101 => @import("scenes/lockbuster3.zig"), // LOCKBUSTER 3, "Lockbuster DMA": letters, panels, two-lane text and YM-volume meters, 320x240 with the bottom border open (ported from the Go re-creation)
    102 => @import("scenes/phenomena.zig"), // PHENOMENA intro (Amiga, Photon/Firefox/Terminator): text pages, logo fade, two per-scanline bars, the photon, the rotating scroller, rasta man.mod (ported from CODEF screen 560)
    103 => @import("scenes/mentalhangover.zig"), // MENTAL HANGOVER (Scoopex, Amiga): circular outline text over the mountain, 49-band per-scanline copper raster (ported from the Go re-creation)
    104 => @import("scenes/gnomes.zig"), // THE GNOMES GROUP "BB25" (Buxton Bytes 2025 Fantasy Cracktro Challenge) intro: the 128-word rainbow overscan, SpongeBob, the cyan TTY and the big scroller (ported from the original ST binary)
    105 => @import("scenes/hmdfac.zig"), // HMD "HMDFAC" (Team Factory tribute): the Falcon 030 intro's color0 flash, the 68k-integer frustum and the wave scroller (ported from the depacked original)
    106 => @import("scenes/replicants_arkanoid2.zig"), // The Replicants / Arkanoid II crack intro (CODEF screen 33)
    else => @compileError("bad cart index"),
};

// Uniform entry: scenes name their struct Demo/Doors/App/Raster — expose one name.
pub const Cart = if (@hasDecl(scene, "Demo")) scene.Demo
else if (@hasDecl(scene, "Doors")) scene.Doors
else if (@hasDecl(scene, "App")) scene.App
else scene.Raster;
