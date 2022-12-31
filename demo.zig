// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const PngDecoder = @import("utils/pngdecoder.zig");
const pal_utils = @import("utils/palette.zig");

extern fn consoleLog(i32) void;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("zigos.zig").HEIGHT;
const WIDTH: usize = @import("zigos.zig").WIDTH;


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var logo_bitmap: [WIDTH*HEIGHT]u8 = undefined;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {

    pub fn init(zigos: *ZigOS) Demo { 

        // convert images
        var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
        const gpa = general_purpose_allocator.allocator();

        var fbs = std.io.fixedBufferStream(@embedFile("assets/logo.png"));
        const reader = fbs.reader();

        var decoder = PngDecoder.PngDecoder(@TypeOf(reader)).init(gpa, reader);   
        defer decoder.deinit();

        if (decoder.parse()) |img| {
            var img_data: [320*200*4]u8 = undefined;
            if (img.bitmap_reader.read(&img_data)) |read| {
                if (read == 0) {
                    logo_bitmap = pal_utils.convertToPaletteMode(&img_data);
                }
            }
            else |_| {}
        } else |_| {}

        // var img = decoder.parse() catch {};
        // var img_data: [320*200*4]u8 = undefined;
        // var read = img.bitmap_reader.read(&img_data);
        // if (read == 0) {
        //     logo_bitmap = pal_utils.convertToPaletteMode(&img_data);
        // }
        
        zigos.nop();

        return .{};
    }
};