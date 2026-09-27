// Native test entry for scene logic.
//
// Scenes embed their assets relative to apps/zig/ (the cart module's root), so a
// scene file cannot be handed to `zig test` directly — the embed would resolve
// outside the module. Importing them from here roots the module correctly.
//
//   zig test apps/zig/scene_tests.zig
test {
    _ = @import("scenes/dbug_sync.zig");
    _ = @import("scenes/union_demo/charly_test.zig");
    _ = @import("scenes/union_demo/return_note.zig");
    _ = @import("scenes/union_demo/hub_note.zig");
    _ = @import("scenes/union_texcopier/copier_test.zig");
    _ = @import("scenes/rno_natrium/verify_test.zig");
    _ = @import("scenes/swedish_newyear/sync_test.zig");
    _ = @import("scenes/swedish_newyear/tcb1_test.zig");
    _ = @import("scenes/swedish_newyear/tcb2_test.zig");
    _ = @import("scenes/swedish_newyear/st.zig");
}
