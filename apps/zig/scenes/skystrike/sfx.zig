// --------------------------------------------------------------------------
// Lines 990-999: the engine note and the effects. Sample 1 is the gun burst
// (looped while firing), sample 2 the crash. nso holds the engine off for a
// few passes while an effect sounds (line 85 re-sets the engine at nso = 1).
// Each routine but 994 starts with WAIT VBL.
//
// ZIG mode (zig_sound.zig): each routine marks its commands with a cue and
// names its own sample; the commands and the game's state are the same.
// --------------------------------------------------------------------------
const snd = @import("sound.zig");
const clock = @import("clock.zig");
const zs = @import("zig_sound.zig");
const V = @import("vars.zig");
const v = &V.v;

/// 990-992: the engine: silent at th = 0, else noise 31 - th under
/// envelope 10 with period eng - 3.
pub fn engine() void {
    clock.waitVbl();
    zs.cue = .engine;
    defer zs.cue = .none;
    snd.samstop();
    if (v.th == 0 and v.nso < 2) snd.volume(0);
    if (v.th != 0) {
        snd.volume(16);
        snd.noise(31 - v.th);
        snd.envel(10, v.eng - 3);
    }
}

/// 993: over water (ew = 1) a splash of noise, else on into 994.
pub fn splash() void {
    clock.waitVbl();
    if (v.ew == 1) {
        zs.cue = .effect;
        defer zs.cue = .none;
        snd.samstop();
        snd.volume(16);
        snd.noise(2);
        snd.envel(9, 19000);
        v.nso = 4;
        zs.play(.splash, false);
        return;
    }
    crashAs(.bomb);
}

/// 994: music off : samloop off : samplay 2 : nso = 6
pub fn crash() void {
    crashAs(.crash);
}

fn crashAs(s: zs.Sample) void {
    zs.cue = .effect;
    defer zs.cue = .none;
    snd.musicOff();
    snd.samloop(false);
    snd.samplay(2);
    v.nso = 6;
    zs.play(s, false);
}

/// 995: the guns: sample 1, looped.
pub fn guns() void {
    clock.waitVbl();
    zs.cue = .effect;
    defer zs.cue = .none;
    snd.musicOff();
    snd.samloop(true);
    snd.samplay(1);
    v.nso = 4;
    zs.play(.gun, true);
}

/// 997: the crash sample and noise 5.
pub fn hit() void {
    clock.waitVbl();
    zs.cue = .effect;
    defer zs.cue = .none;
    snd.musicOff();
    snd.samloop(false);
    snd.samplay(2);
    snd.noise(5);
    v.nso = 4;
    zs.play(.hit, false);
}

/// 998: the crash sample.
pub fn bang() void {
    clock.waitVbl();
    zs.cue = .effect;
    defer zs.cue = .none;
    snd.musicOff();
    snd.samloop(false);
    snd.samplay(2);
    v.nso = 4;
    zs.play(.bang, false);
}
