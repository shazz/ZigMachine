// Native test entry for scene logic.
//
// Scenes embed their assets relative to apps/zig/ (the cart module's root), so a
// scene file cannot be handed to `zig test` directly — the embed would resolve
// outside the module. Importing them from here roots the module correctly.
//
//   zig test apps/zig/scene_tests.zig
test {
    _ = @import("scenes/dbug_sync.zig");
}
