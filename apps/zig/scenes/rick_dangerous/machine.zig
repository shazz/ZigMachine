// --------------------------------------------------------------------------
// The game as the scene runs it: power-on (the start-up and the first title),
// then the main loop, frame after frame, each resumable at its waits.
//
//   reset()        the entry image, the start-up $3D6AC
//   run(limit)     run the game up to the host's time `limit` (in VBLs): it
//                  stops at the first wait that would pass it
//   runFrame()     lockstep: one whole frame of the loop (the harness)
// --------------------------------------------------------------------------
const m = @import("ram.zig");
const F = @import("fields.zig");
const game = @import("game.zig");
const io = @import("io.zig");
const clock = @import("clock.zig");
const digi = @import("digi.zig");
const snd = @import("sound.zig");
const handlers = @import("handlers.zig");
const loop = @import("loop.zig");
const title = @import("title.zig");

/// The harness's entry: the game's first instruction at 28,892 cycles into a VBL.
const ENTRY_POS: i64 = 28892;

pub var frame: loop.Frame = .{};
var boot: title.Title = .{};
var booting: bool = false;
/// Frames of the loop run since power-on / the harness's load.
pub var frames: u64 = 0;

fn clearState() void {
    game.pal = [_]i64{0} ** 16;
    game.vbase = 0xF8000;
    game.frame_vbls = 0;
    game.call_vbls = 0;
    game.vbls = 0;
    game.limit = 0;
    game.paused = false;
    clock.reset();
    digi.reset();
    snd.log_n = 0;
    snd.subtune = 0;
    snd.stop = false;
    handlers.unknown = 0;
    frames = 0;
    frame = .{};
}

/// Power-on: the entry image, the start-up, the first title.
pub fn reset() void {
    m.loadImage();
    clearState();
    io.lockstep = false;
    clock.startAt(ENTRY_POS);
    boot.boot();
    booting = true;
}

/// Run until the host's time `limit` (VBLs): stops at the first wait past it.
pub fn run(limit: u64) void {
    game.limit = limit;
    var guard: u32 = 0;
    while (guard < 100_000) : (guard += 1) {
        if (booting) {
            if (boot.step() == .yield) return;
            booting = false;
            frame.start();
        }
        if (frame.pc == .done) frame.start();
        if (frame.step() == .yield) return;
        frames += 1;
        frame.pc = .done;
    }
}

/// The harness's load: a key frame's snapshot is in the memory already.
pub fn loadLockstep(pal: [16]i64, vbase: i64) void {
    clearState();
    game.pal = pal;
    game.vbase = vbase;
    booting = false;
    io.lockstep = true;
}

/// Lockstep: one frame of the loop. Returns the VBLs it took.
pub fn runFrame() u32 {
    snd.log_n = 0;
    frame.start();
    _ = frame.step();
    frames += 1;
    return game.frame_vbls;
}

/// The title / hall of fame alternation is up (Escape leaves the cart there).
pub fn onTitle() bool {
    if (booting) return true;
    return frame.pc == .c21 and frame.title.pc != .done and @intFromEnum(frame.title.pc) <= @intFromEnum(@TypeOf(frame.title.pc).hold2);
}

pub fn keyByte() i64 {
    return m.rb(F.KEY);
}
