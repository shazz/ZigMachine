// --------------------------------------------------------------------------
// The BARD queue's FM device (sid_live.zig $C000..$C3FF; docs/project/DECISIONS.md 2026-11-24 "The
// BARD queue's FM device"): a cart's timed writes to the YM2612 + SN76489 of the VGM engine, on the
// channels it owns, while the VGM player plays the tune on the others (libs/c/vgm/zm_vgm_sfx.c).
//
// The queue anchors the cart's stamps as for every device (cart_paula_queue.zig); then, unlike the
// SID and AY devices, the writes go ahead to the engine's own ring at once, with their stamp on the
// output clock the engine counts from the device's on (`base`: the queue's `now` then). The engine
// applies each at the engine frame its output stage reaches at that stamp, so where a write lands
// depends on its stamp only, not on when it came or on the host's render size, as long as it comes
// before the engine renders that frame (~430 samples ahead of the output: a cart lead of >= 1024).
// A full engine ring keeps the rest in the queue for the next render. Marks wait in Live.marks and
// come back when their sample comes, as on the other devices.
//
// The VGM player (vgm.zig) calls feed before each render and played after it.
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const sid_live = @import("sid_live.zig");

const Live = sid_live.Live;

/// Every queued write to the engine (in order), until its ring or the marks' hold is full.
pub fn feed(l: *Live, base: u32) void {
    while (l.queue.front()) |e| {
        if (e.addr == sid_live.OP_MARK) {
            if (l.nmarks == Live.MARKS) return; // the hold is full: the rest waits behind this mark
            l.marks[l.nmarks] = e;
            l.nmarks += 1;
        } else if (l.classify(e) == .fm) {
            const at = l.queue.local(e.t) -% base;
            if (audio.machineVgmSfxPush(at, e.addr - sid_live.FM_BASE, e.value) == 0) return; // full: next render
        }
        l.queue.pop();
    }
}

/// `n` output frames rendered: the queue's clock moves on; the marks whose sample has come say so.
pub fn played(l: *Live, n: u32) void {
    l.queue.advance(n);
    var kept: u32 = 0;
    for (l.marks[0..l.nmarks]) |e| {
        const ahead: i32 = @bitCast(l.queue.local(e.t) -% l.queue.now);
        if (ahead <= 0 and kept == 0) {
            _ = l.classify(e);
        } else {
            l.marks[kept] = e;
            kept += 1;
        }
    }
    l.nmarks = kept;
}
