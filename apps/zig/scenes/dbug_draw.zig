// --------------------------------------------------------------------------
// D-BUG screen — pixel helpers, split out of dbug.zig for the file-size budget
// (same arrangement as st_replay's draw/ui split).
// --------------------------------------------------------------------------
const zg = @import("zigos");

const RenderTarget = zg.RenderTarget;

pub const OVERSCAN_W: u16 = 400;
pub const ZOOM: u16 = 8;

/// Blow the narrow scrolltext strip up by ZOOM in both axes into the overscan
/// page, its top edge at `top`. The strip is rendered 50 px wide precisely so
/// that 50*8 == 400 covers the opened borders as well.
pub fn zoomScroller(dst: RenderTarget, src: RenderTarget, top: u16, rows: u16) void {
    const strip = src.render_buffer;
    const page = dst.render_buffer;
    const start = @as(u32, top) * OVERSCAN_W;

    var char_row: u32 = 0;
    while (char_row < rows) : (char_row += 1) {
        const strip_row = char_row * strip.width;
        const block = start + char_row * ZOOM * OVERSCAN_W;

        var row: u32 = 0;
        while (row < ZOOM) : (row += 1) {
            const line = block + row * OVERSCAN_W;
            var col: u32 = 0;
            while (col < strip.width) : (col += 1) {
                const pal_entry = strip.buffer[strip_row + col];
                const out = line + col * ZOOM;
                if (out + ZOOM > page.buffer.len) return;
                @memset(page.buffer[out .. out + ZOOM], pal_entry);
            }
        }
    }
}
