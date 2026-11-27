// Native test entry for scene logic.
//
// Scenes embed their assets relative to apps/zig/ (the cart module's root), so a
// scene file cannot be handed to `zig test` directly — the embed would resolve
// outside the module. Importing them from here roots the module correctly.
//
//   zig test apps/zig/scene_tests.zig
test {
    _ = @import("racer_tests.zig"); // RACER (R82 M1): track loader, PVS = DDA, edge rule, clip, sort, bench
    _ = @import("scenes/fuji_hobbytronic/fixed.zig");
    _ = @import("scenes/obj/tests.zig");
    _ = @import("scenes/obj/raster_tests.zig");
    _ = @import("scenes/obj/nest_tests.zig");
    _ = @import("scenes/sysinfo/grid.zig");
    _ = @import("scenes/notepad/doc_test.zig"); // NOTEPAD's text, cursor, selection, clipboard, find
    _ = @import("scenes/notepad/names.zig");
    // SID-WIZARD Z: the editor library (74 tests of the port) and the host's pure parts; player_test.zig needs the cpu6502 module (build.sh runs it with --dep)
    _ = @import("scenes/sidwizard_z/swm_test.zig");
    _ = @import("scenes/sidwizard_z/display_test.zig");
    _ = @import("scenes/sidwizard_z/keys_test.zig");
    _ = @import("scenes/sidwizard_z/menu_test.zig");
    _ = @import("scenes/sidwizard_z/filer_test.zig");
    _ = @import("scenes/sidwizard_z/startup_test.zig");
    _ = @import("scenes/sidwizard_z/border_test.zig");
    _ = @import("scenes/sidwizard_z/frame_test.zig");
    _ = @import("scenes/sidwizard_z/editor_test.zig");
    _ = @import("scenes/sidwizard_z/keymap.zig");
    _ = @import("scenes/sidwizard_z/names.zig");
    _ = @import("scenes/sidwizard_z/video.zig");
    _ = @import("scenes/sidwizard_z/follow.zig");
    _ = @import("scenes/sidwizard_z/scope.zig");
    _ = @import("scenes/sysinfo/stref.zig");
    _ = @import("scenes/sysinfo/refs.zig");
    _ = @import("scenes/sysinfo/view.zig");
    _ = @import("scenes/sysinfo/diskinfo.zig");
    _ = @import("scenes/sysinfo/sound_list.zig");
    _ = @import("scenes/dbug_sync.zig");
    _ = @import("scenes/stcs_wave.zig");
    _ = @import("scenes/stniccc/rewind_test.zig");
    _ = @import("scenes/union_demo/charly_test.zig");
    _ = @import("scenes/union_demo/return_note.zig");
    _ = @import("scenes/union_demo/hub_note.zig");
    _ = @import("scenes/union_texcopier/copier_test.zig");
    _ = @import("scenes/rno_natrium/verify_test.zig");
    _ = @import("scenes/rno_natrium/zig_math_test.zig");
    _ = @import("scenes/lockbuster2/engine_test.zig");
    _ = @import("scenes/lockbuster2/chunky_test.zig");
    _ = @import("scenes/chonchon/chunky_test.zig");
    _ = @import("scenes/chonchon2/chunky_test.zig");
    _ = @import("scenes/larcociel5/chunky_test.zig");
    _ = @import("scenes/larcociel2/present_test.zig");
    _ = @import("scenes/raytrace/colour_test.zig");
    _ = @import("scenes/raytrace/gfa_test.zig"); // the GfA Punch listing's FN a/c/d, RAND, line 7
    _ = @import("scenes/raytrace/astro/bits_test.zig");
    _ = @import("scenes/noextra/assets.zig");
    _ = @import("scenes/noextra/timeline.zig");
    _ = @import("scenes/swedish_newyear/sync_test.zig");
    _ = @import("scenes/swedish_newyear/tcb1_test.zig");
    _ = @import("scenes/swedish_newyear/tcb1_mirror_test.zig");
    _ = @import("scenes/swedish_newyear/tcb2_test.zig");
    _ = @import("scenes/swedish_newyear/omega_test.zig");
    _ = @import("scenes/swedish_newyear/st.zig");
    _ = @import("scenes/swedish_newyear/st_align.zig");
    _ = @import("scenes/ulm_dsots/view.zig");
    _ = @import("scenes/ulm_dsots/level.zig");
    _ = @import("scenes/ulm_dsots/griffin_test.zig");
    _ = @import("scenes/snyd_90/menu_test.zig");
    _ = @import("scenes/snyd_90/f2_test.zig");
    _ = @import("scenes/snyd_90/f1_test.zig");
    _ = @import("scenes/hippel_musicdisk/copper_test.zig");
    _ = @import("scenes/snyd_90/f3_test.zig");
    _ = @import("scenes/snyd_90/f4_test.zig");
    _ = @import("scenes/snyd_90/f5_test.zig");
    _ = @import("scenes/snyd_90/f6_test.zig");
    _ = @import("scenes/snyd_90/chunky.zig");
    _ = @import("scenes/snyd_90/f4_ops.zig");
    _ = @import("scenes/dune_gen4/bounce.zig");
    _ = @import("scenes/dune_gen4/fade.zig");
    _ = @import("scenes/dune_gen4/tny.zig");
    _ = @import("scenes/dune_gen4/hades/ram.zig");
    _ = @import("scenes/dune_gen4/hades/stars.zig");
    _ = @import("scenes/dune_gen4/hades/logo.zig");
    _ = @import("scenes/dune_gen4/hades/skulls.zig");
    _ = @import("scenes/dune_gen4/hades/scroll.zig");
    _ = @import("scenes/naos_nitrowave/planar.zig");
    _ = @import("scenes/tcb_colorshock/inkpal_test.zig");
    _ = @import("scenes/badapple/decoder_test.zig");
    _ = @import("scenes/badapple/tiles_test.zig");
}
