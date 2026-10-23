// --------------------------------------------------------------------------
// The headless harness's door into PHENOMENA (apps/phenomena_headless.mjs):
// every state word the sequence and the scroller touch. Pulled in only when
// this scene IS the cart (phenomena.zig checks cart.Cart), so these exports
// never leak into another cart's build. Pixels are read from the machine's
// raster, not from here.
// --------------------------------------------------------------------------
const app = @import("app.zig");
const seq = @import("seq.zig");
const dna = @import("dna.zig");
const dna_draw = @import("dna_draw.zig");

export fn phOk() u32 {
    return @intFromBool(app.ok);
}

/// 0 phase, 1 percent, 2 direction, 3 rb2, 4 drop_n, 5 color3, 6 t, 7 rect_w,
/// 8 rect_show, then the drawn view: 9 phase, 10 level, 11 rb2, 12 photon,
/// 13 hue, 14 rect_w, 15 t.
export fn phSeq(k: u32) i32 {
    const v = seq.view;
    return switch (k) {
        0 => @intFromEnum(seq.phase),
        1 => seq.percent,
        2 => seq.direction,
        3 => seq.rb2,
        4 => seq.drop_n,
        5 => @intCast(seq.color3),
        6 => @intCast(seq.t),
        7 => seq.rect_w,
        8 => @intFromBool(seq.rect_show),
        9 => @intFromEnum(v.phase),
        10 => v.level,
        11 => v.rb2,
        12 => v.photon,
        13 => @intCast(v.hue),
        14 => v.rect_w,
        15 => @intCast(v.t),
        else => -999,
    };
}

/// 0 head, 1 len, 2 msgIndex, 3 sliceCount, 4 pause, 5 pauseTime,
/// 6 scrollSpeed, 7 rotSpeed (twentieths).
export fn phDna(k: u32) i32 {
    return switch (k) {
        0 => dna.head,
        1 => dna.len,
        2 => dna.msg_index,
        3 => dna.slice_count,
        4 => @intFromBool(dna.pause),
        5 => dna.pause_time,
        6 => dna.scroll_speed,
        7 => dna.rot_speed,
        else => -999,
    };
}

/// Queue element i (0 = head): 0 glyph, 1 frm (twentieths), 2 slice.
export fn phCell(i: u32, k: u32) i32 {
    const c = dna.cell(i);
    return switch (k) {
        0 => dna.chr[c],
        1 => dna.frm[c],
        2 => dna.slc[c],
        else => -999,
    };
}

/// Slice i's strip top as last drawn, cnvScroller rows Q16.16.
export fn phStripTop(i: u32) i32 {
    return dna_draw.top_q16[i];
}
