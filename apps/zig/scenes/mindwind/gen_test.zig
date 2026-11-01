// The start-up generators against the running demo: the SHA-256 of what the depacked
// MINDWIND.TOS left in RAM (Hatari, STE, VBL 7319, both buffers turned chunky with
// stripes_gen.toChunky's convention), so a transcription slip anywhere shows here.
//   zig test apps/zig/scenes/mindwind/gen_test.zig
const std = @import("std");
const stripes = @import("stripes_gen.zig");
const rainbow = @import("rainbow_gen.zig");

// A native test cannot @embedFile outside its directory: the data is read from the repo root.
const DATA = "apps/zig/assets/screens/mindwind/";

fn load(a: std.mem.Allocator, name: []const u8) ![]u8 {
    var path: [128]u8 = undefined;
    const p = try std.fmt.bufPrint(&path, "{s}{s}", .{ DATA, name });
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, p, a, .limited(1 << 16));
}

fn hex(digest: [32]u8) [64]u8 {
    return std.fmt.bytesToHex(digest, .lower);
}

test "the stripe workspace and bank equal the demo's" {
    const a = std.testing.allocator;
    const patterns = try load(a, "stripe_patterns.bin");
    defer a.free(patterns);
    const w = try a.alloc(u16, stripes.PLANAR_WORDS);
    defer a.free(w);
    const out = try a.alloc(u8, stripes.ROWS * stripes.ROW_PX);
    defer a.free(out);
    stripes.generate(w, patterns[0..256], out);
    var d: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(out, &d, .{});
    try std.testing.expectEqualStrings("2f4e8f87172513d41bb6106638fad126a821b4f78264945945c8542817baf432", &hex(d));
}

test "the three rainbow images equal the demo's" {
    const want = [3][]const u8{
        "6c3519487745437ed7f40e0c8ef6931c7fe7d8c42f28005c3c88938d75b76d97",
        "60e47202aff0a38979ca69ac2fa97144df5f88570fe49c1c593d1bbdae942404",
        "89911b9285e389274f102babe3f7fac5aa0ba5aed54cf9cf488e40cf3ae52386",
    };
    const a = std.testing.allocator;
    const sin_271c8 = try load(a, "sin_271c8.bin");
    defer a.free(sin_271c8);
    const out = try a.alloc(u8, rainbow.IMAGE_BYTES);
    defer a.free(out);
    for (0..3) |i| {
        rainbow.generate(@enumFromInt(i), sin_271c8, out);
        var d: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(out, &d, .{});
        try std.testing.expectEqualStrings(want[i], &hex(d));
    }
}
