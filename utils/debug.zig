const builtin = @import("builtin");

const console_native = @import("debug_native.zig").Console;
const console_js = @import("JS.zig").Console;

pub const Console = switch(builtin.cpu.arch) {
    .wasm32, .wasm64 => console_js,
    else => console_native
};