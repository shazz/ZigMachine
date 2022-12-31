// --------------------------------------------------------------------------
// Imports
// --------------------------------------------------------------------------
const std = @import("std");
const ZigOS = @import("zigos.zig").ZigOS;
const PngDecoder = @import("utils/pngdecoder.zig");
const pal_utils = @import("utils/palette.zig");

const consoleLog = @import("utils/debug.zig").consoleLog;

// --------------------------------------------------------------------------
// Constants
// --------------------------------------------------------------------------
const HEIGHT: usize = @import("zigos.zig").HEIGHT;
const WIDTH: usize = @import("zigos.zig").WIDTH;


// --------------------------------------------------------------------------
// Variables
// --------------------------------------------------------------------------
var logo_bitmap: []u8 = undefined;

// --------------------------------------------------------------------------
// Demo
// --------------------------------------------------------------------------
pub const Demo = struct {

    pub fn init() !Demo { 

        consoleLog("demo init");

        // convert images
        var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
        var gpa = general_purpose_allocator.allocator();

        var fbs = std.io.fixedBufferStream(@embedFile("assets/logo_tc.png"));
        const reader = fbs.reader();

        var decoder = PngDecoder.PngDecoder(@TypeOf(reader)).init(gpa, reader);   
        defer decoder.deinit();

        consoleLog("Parsing PNG file");
        var img = try decoder.parse();

        consoleLog("Read decoded data");

        var img_data = try img.bitmap_reader.readAllAlloc(gpa, std.math.maxInt(usize));
        
        consoleLog("Allocating buffer for palette data");
        logo_bitmap = try gpa.alloc(u8, img.width*img.height);

        consoleLog("Converting to palette mode");
        pal_utils.convertToPaletteMode(&img_data, &logo_bitmap);

        // var img_data: [320*200*4]u8 = undefined;
        // var read = try img.bitmap_reader.read(&img_data);

        // if (read == 0) {
        //     pal_utils.convertToPaletteMode(&img_data, &logo_bitmap);
        // }

        // if (decoder.parse()) |img| {
        //     var img_data: [320*200*4]u8 = undefined;
        //     if (img.bitmap_reader.read(&img_data)) |read| {
        //         if (read == 0) {
        //             logo_bitmap = pal_utils.convertToPaletteMode(&img_data);
        //         }
        //     }
        //     else |_| {}
        // } else |_| {}

        return .{ };
    }

    pub fn deinit() void {
        var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
        var gpa = general_purpose_allocator.allocator();
        defer gpa.free(logo_bitmap);
    }
};