// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Demo = @import("demo.zig").Demo;
const Console = @import("utils/debug.zig").Console;

// --------------------------------------------------------------------------
// Types
// --------------------------------------------------------------------------
const Resolution = @import("zigos.zig").Resolution;
const Color = @import("zigos.zig").Color;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("zigos.zig").HEIGHT;
const WIDTH: usize = @import("zigos.zig").WIDTH;
const VERSION = "0.1";

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var zigos: ZigOS = undefined;
var demo: Demo = undefined;

pub fn main() !void {
    Console.log("ZigMachine v. {s}\n", .{VERSION});

    zigos.init();
    demo.init(&zigos);
}
