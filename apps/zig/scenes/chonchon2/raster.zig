// --------------------------------------------------------------------------
// The two per-scanline colour tables -- internal/demo/game.go's updateRasters.
//
// The Go builds a 200-word Background raster and a 200-word Foreground raster
// every tick:
//
//   Background = raster-background.bin
//   Background[68..158] = raster-program.bin[frame*180 .. +180]
//   Foreground = raster-base.bin
//   Foreground[OldY..OldY+21] = raster-scroll.bin
//
// then converts each word to RGBA on the channels-nibble*34 scale. The shader
// picks Background[y] for index 0 and Foreground[y] for index 2, which is why
// the cart's HBL writes exactly entries 0 and 2 for every visible line.
//
// raster-program.bin holds 506 frames; past those the Go uses
// 25 + (tick - 506) % (506 - 25), i.e. it skips the first 25 frames and loops
// the remaining 481.
// --------------------------------------------------------------------------
const assets = @import("assets.zig");

pub const program_frames: u32 = assets.raster_program.len / 180;

pub var bg: [200]u32 = undefined;
pub var fg: [200]u32 = undefined;

pub fn update(tick: u32, old_y: i32) void {
    var bgw: [200]u16 = undefined;
    var fgw: [200]u16 = undefined;
    var y: usize = 0;
    while (y < 200) : (y += 1) {
        bgw[y] = assets.beWord(assets.raster_bg, y * 2);
        fgw[y] = assets.beWord(assets.raster_base, y * 2);
    }

    var frame = tick;
    if (frame >= program_frames)
        frame = 25 + (frame - program_frames) % @max(1, program_frames - 25);
    const at = @as(usize, frame) * 180;
    var i: usize = 0;
    while (i < 90) : (i += 1)
        bgw[68 + i] = assets.beWord(assets.raster_program, at + i * 2);

    const scroll_at = old_y * 2;
    if (scroll_at >= 0 and scroll_at + @as(i32, @intCast(assets.raster_scroll.len)) <= 400) {
        const o: usize = @intCast(scroll_at);
        i = 0;
        while (i < assets.raster_scroll.len / 2) : (i += 1)
            fgw[o / 2 + i] = assets.beWord(assets.raster_scroll, i * 2);
    }

    y = 0;
    while (y < 200) : (y += 1) {
        bg[y] = assets.rgbw(bgw[y]);
        fg[y] = assets.rgbw(fgw[y]);
    }
}
