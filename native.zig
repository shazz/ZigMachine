

// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const LogicalFB = @import("zigos.zig").LogicalFB;
const Demo = @import("demo.zig").Demo;
const consoleLog = @import("utils/debug.zig").consoleLog;

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

// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var zigos: ZigOS = undefined;
var demo: Demo = undefined;


pub fn main() !void {

    std.debug.print("Hello, {s}!\n", .{"World"});

    zigos = ZigOS.create();
    zigos.init();
    if (Demo.init()) |aDemo| {
        demo = aDemo;
    } 
    else |_| {
        
    }
}
