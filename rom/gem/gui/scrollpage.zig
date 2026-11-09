// --------------------------------------------------------------------------
// A click in a scroll TRACK, off its slider: GEM pages (WM_ARROWED's WA_UPPAGE /
// WA_DNPAGE / WA_LFPAGE / WA_RTPAGE). The content moves by one window's worth,
// `vpage` / `hpage` in the owner's units, towards the click, clamped to 0..max.
// Matt on the board, 9 Nov: "when clicking on the scrollbar (not the arrows), did
// nothing". The slider itself drags (window.zig handleSlider); the arrows step.
// --------------------------------------------------------------------------
const types = @import("types.zig");
const Window = types.Window;
const inRect = types.inRect;

/// A press at (px, py) on `w`'s vertical or horizontal track, outside its slider:
/// page that way and return true. Whatever else it hit is not this gadget's.
pub fn trackPress(w: *Window, px: i32, py: i32) bool {
    if (w.vmax > 0 and w.vslide < 1000) {
        const tr = types.vTrack(w);
        if (inRect(tr, px, py)) {
            const b = types.sliderBox(tr, w.vslide, w.vscroll, w.vmax, true);
            if (inRect(b, px, py)) return false;
            w.vscroll = step(w.vscroll, w.vpage, w.vmax, py < b.y);
            return true;
        }
    }
    if (w.hmax > 0 and w.hslide < 1000) {
        const tr = types.hTrack(w);
        if (inRect(tr, px, py)) {
            const b = types.sliderBox(tr, w.hslide, w.hscroll, w.hmax, false);
            if (inRect(b, px, py)) return false;
            w.hscroll = step(w.hscroll, w.hpage, w.hmax, px < b.x);
            return true;
        }
    }
    return false;
}

fn step(at: i16, page: i16, max: i16, back: bool) i16 {
    const p = @max(1, page);
    return if (back) @max(0, at - p) else @min(max, at + p);
}
