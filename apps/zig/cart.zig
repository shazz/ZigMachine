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
    2 => @import("scenes/union/doors.zig"),
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
    else => @compileError("bad cart index"),
};

// Uniform entry: scenes name their struct Demo/Doors/App/Raster — expose one name.
pub const Cart = if (@hasDecl(scene, "Demo")) scene.Demo
else if (@hasDecl(scene, "Doors")) scene.Doors
else if (@hasDecl(scene, "App")) scene.App
else scene.Raster;
