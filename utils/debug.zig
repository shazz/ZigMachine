const builtin = @import("builtin");

const debug_native = @import("debug_native.zig");
const debug_wasm = @import("debug_wasm.zig");

pub const consoleLog = switch(builtin.cpu.arch) {
    .wasm32, .wasm64 => debug_wasm.consoleLog,
    else => debug_native.consoleLog
};