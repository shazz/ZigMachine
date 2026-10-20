// --------------------------------------------------------------------------
// CHONCHON 2 -- the olivierh59500/go-chonchon2 Go/Ebitengine re-creation,
// ported to the ZigMachine. See chonchon2/app.zig for the screen and its
// hardware mapping; this file only exposes the cart's uniform `Demo`.
// --------------------------------------------------------------------------
const app = @import("chonchon2/app.zig");

pub const Demo = app.Demo;

// The harness's exports exist only when this scene IS the registered cart.
comptime {
    if (@import("../cart.zig").Cart == Demo) {
        _ = @import("chonchon2/testapi.zig");
    }
}
