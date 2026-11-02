// --------------------------------------------------------------------------
// demo-audio.wasm: the four Paula channels lent to a CART (HW 1.14.0,
// decisions.md 2026-11-02 "Paula channels for carts").
//
// A cart that wants the Amiga's sound chip (pt2-clone, a tracker, an Amiga-
// style game) claims the channels and then writes Paula's registers, exactly
// as an Amiga program does: AUDxLC/LEN/PER/VOL and DMACON, through paula.zig,
// the same model the Hippel player's 68000 drives (LC/LEN latched at the DMA
// start and at each wrap, so "attack, then loop" and sample swaps are the
// hardware's). The host side (docs/sealed-loader.js + audio-worklet-sealed.js,
// fpga/host/audio_bridge.c + audio_paula.c) only carries the bytes:
//   claim    every player stops; chip RAM (song RAM, 1 MiB) is zeroed; while the
//            cart holds the channels the hosts refuse every song, stream and effect
//   upload   cart bytes copied into chip RAM at an offset: the samples, as an
//            Amiga program copies them into chip RAM; LC is a chip RAM offset
//   write    the frame's register writes, each at the cart's sample (cart_paula_queue)
//   release  (or the machine's reset on the next cart) the channels go back
// --------------------------------------------------------------------------
const audio = @import("audio_hw");
const players = @import("players");
const m = @import("root");
const paula = players.paula;
const cq = players.cart_paula_queue;

/// The cart holds the channels.
pub var claimed: bool = false;
var queue: cq.Queue = .{};
/// The host copies a batch here, then calls audioPaulaQueue(n).
const STAGE: u32 = 512;
var stage: [STAGE]cq.Entry = undefined;
/// Writes to an address Paula does not have (counted, never applied).
var refused: u32 = 0;
var applied: u32 = 0;

/// Take the channels: everything else stops, chip RAM is zeroed (a never-uploaded
/// region plays silence), the voices are off. `lead`: the most samples the cart's
/// batches may arrive after their first write (its longest frame), clamped.
/// Always 1: the cart wins; the hosts refuse the players while it holds them.
export fn audioPaulaClaim(lead: u32) u32 {
    if (m.sndh.active) m.sndh.abandon(); // its EXIT would run over the zeroed RAM
    m.stopAll();
    audio.machineAudioReset();
    const chip: [*]u8 = @ptrFromInt(audio.SONG_BASE);
    @memset(chip[0..audio.SONG_CAP], 0);
    paula.reset(false);
    paula.cart_ext = true;
    queue.reset(lead);
    refused = 0;
    applied = 0;
    claimed = true;
    m.current_mode = 1; // the four channels' scope view, as a MOD's
    return 1;
}

/// Give the channels back: the voices off, the queue dropped.
pub fn release() void {
    if (!claimed) return;
    paula.reset(false);
    queue.reset(queue.lead);
    claimed = false;
    if (m.current_mode == 1) m.current_mode = 0;
}

export fn audioPaulaRelease() void {
    release();
}

export fn audioPaulaClaimed() u32 {
    return @intFromBool(claimed);
}

/// Chip RAM, where uploads land: [ChipPtr, ChipPtr + ChipSize) of this memory.
export fn audioPaulaChipPtr() u32 {
    return @intCast(audio.SONG_BASE);
}
export fn audioPaulaChipSize() u32 {
    return @intCast(audio.SONG_CAP);
}

export fn audioPaulaStagePtr() u32 {
    return @intCast(@intFromPtr(&stage));
}
export fn audioPaulaStageCap() u32 {
    return STAGE;
}

/// The `n` staged writes, queued for their samples. Returns those taken (0 unclaimed).
export fn audioPaulaQueue(n: u32) u32 {
    if (!claimed) return 0;
    return queue.push(stage[0..@min(n, STAGE)]);
}

export fn audioPaulaApplied() u32 {
    return applied;
}
export fn audioPaulaRefused() u32 {
    return refused;
}
export fn audioPaulaResyncs() u32 {
    return queue.resyncs;
}
export fn audioPaulaDropped() u32 {
    return queue.dropped;
}
export fn audioPaulaLatches() u32 {
    return paula.latches;
}

fn apply(e: cq.Entry) void {
    const ok = e.addr >= paula.BASE and e.addr < paula.BASE + paula.SIZE and
        paula.write16(e.addr, @truncate(e.value));
    if (ok) applied +%= 1 else refused +%= 1;
}

/// audioRender while claimed: each write at its sample, a voice re-latched at its wrap.
pub fn render(frames: usize) void {
    const n: u32 = @intCast(@min(frames, audio.MAX_FRAMES));
    audio.machineClear(n);
    var off: u32 = 0;
    while (off < n) {
        while (queue.due()) |e| apply(e);
        const block = @max(1, @min(queue.untilNext(n - off), paula.samplesToLatch(n - off)));
        audio.machineMixPaula(off, block);
        paula.advance(block);
        queue.advance(block);
        off += block;
    }
    audio.machineClamp(n);
}
