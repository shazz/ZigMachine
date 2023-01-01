export fn renderPhysicialFrameBuffer(fb_name: [*]const u8) void {
}


var arrays: [4]*u32 = undefined;
var first_array: [64000]u8 = undefined;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const bytes = try allocator.alloc(u8, 64000);
arrays[0] = &bytes;

for (arrays) |an_array| {
    for (an_array) |val| {
        _ = val // val is each u8 from the 64000 u8 of first_array
    }
}


const an_array: [64000]u8 = arrays[array_id];
var i: u16 = 0;

for (physical_framebuffer) |*row| {
    for (row) |*pixel| {

        const pal_entry: u8 = an_array[i];
        const pal_value: Color = zigos.palette[pal_entry];

        pixel.*[0] = pal_value.r;
        pixel.*[1] = pal_value.g;
        pixel.*[2] = pal_value.b;
        pixel.*[3] = pal_value.a;   

        i += 1;
    }
}

extern fn consoleLogJS(ptr: [*]const u8, len: usize) void;

pub fn consoleLog(s: []const u8) void {
    consoleLogJS(s.ptr, s.len);
}

