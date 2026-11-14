//! zigdemo: the demo engine (the generic parts of The Black Lotus's demo system,
//! from their PSP demo Suicide Barbie, MIT). Umbrella for the modules; see README.md.

pub const clock = @import("clock.zig");
pub const timeline = @import("timeline.zig");
pub const curve = @import("curve.zig");
pub const part = @import("part.zig");
pub const demo = @import("demo.zig");
pub const debug = @import("debug.zig");
pub const assets = @import("assets.zig");
pub const audio = @import("audio.zig");
pub const r3d = @import("r3d.zig");

pub const Demo = demo.Demo;
