
extern fn consoleLogJS(ptr: [*]const u8, len: usize) void;

pub fn consoleLog(s: []const u8) void {
    consoleLogJS(s.ptr, s.len);
}