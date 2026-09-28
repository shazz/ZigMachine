// SKYSTRIKE ZIG-mode harness, part 1 (apps/skystrike_zig.mjs is the driver):
// a lockstep session with ZIG's door (apps/zig/scenes/skystrike/zig_testapi.zig)
// on top of the ORIGINAL harness's (apps/skystrike_session.mjs), and a flight
// driven PASS by PASS, so a run in ORIGINAL and one in ZIG see the same input
// at the same point of the game however many VBLs their passes take.
import { session, toPlay, PASSES } from "./skystrike_session.mjs";

export const Z = {
    crc: 300, zig: 301, view: 302, liveSx: 303, liveAl: 304, draws: 305, cx: 306, base: 307,
    valid: 308, slots: 309, rebuilds: 310, shifts: 311, sx: 312, sy: 313, camX: 314, camY: 315,
    renders: 316, leaks: 317, sent: 318, sent0: 320, cratersMade: 364, cratersFilled: 365,
    sit: 372, playing: 373, tune: 374, fxRefused: 375, credits: 376,
    gainPlay: 377, gainMenus: 378, gainGameOver: 379, psgVoices: 380,
};
export const RING_W = 960, RING_H = 540, WIN_W = 400, WIN_H = 280;
export const CLEAR_SENT = 13;
export const CRATER_LIFE = 370; // zig_testapi.zig: the setting, in VBLs
const DT = 20; // ms: one ST VBL, so a frame() in lockstep is one displayed frame

/// A session in `zig` mode (the lockstep power-on is ORIGINAL), with the
/// capture of each live draw's back screen on.
export async function zsession(zig, seed = 1234) {
    const s = await session(seed);
    s.demo.skyTestCapture(1);
    s.mode = (m) => s.demo.skyTestMode(m ? 1 : 0);
    s.mode(zig);
    // Craters never fill in (as in ORIGINAL): the one ZIG setting that is
    // gameplay (zig_craters.zig). apps/skystrike_zig_craters.mjs turns it on.
    s.poke(CRATER_LIFE, 0);
    s.z = (k) => s.val(Z[k]);
    /// n VBLs, each followed by one displayed frame (what the host does).
    s.run = (n, each) => {
        for (let i = 0; i < n; i++) { s.vbl(1); s.machine.hwClear(); s.demo.frame(DT); each?.(); }
    };
    /// VBLs until the pass counter moves: one main-loop pass. Returns its VBLs.
    s.pass = (each) => {
        const p = s.val(PASSES);
        for (let n = 1; n < 400; n++) { s.run(1, each); if (s.val(PASSES) !== p) return n; }
        throw new Error(`no main-loop pass in 400 VBLs (label ${s.label()})`);
    };
    s.ring = () => new Uint8Array(s.memory.buffer, s.demo.skyTestPtr(5), RING_W * RING_H);
    s.capture = () => new Uint8Array(s.memory.buffer, s.demo.skyTestPtr(6), 64000);
    s.overlay = () => new Uint8Array(s.memory.buffer, s.demo.skyTestPtr(7), WIN_W * WIN_H);
    s.sent = () => { const o = []; for (let i = 0; i < s.z("sent"); i++) o.push(s.val(Z.sent0 + i)); return o; };
    return s;
}

/// To the runway of mission 1 (Easy), in play at line 50.
export async function onRunway(zig, seed) {
    const s = await zsession(zig, seed);
    await toPlay(s);
    if (!s.runTo("l50", 2000)) throw new Error(`not in play (label ${s.label()})`);
    return s;
}

/// Throttle 9 and take off (the plane leaves the runway flying left), then
/// `passes` passes. Same input, same pass, in either mode.
export function takeOff(s, passes, each) {
    s.press(57); // '9'
    for (let i = 0; i < passes; i++) s.pass(each);
}

/// The heading (0 left, 4 up, 8 right, 12 down): r and r2 as 80-87 leave them.
export function steer(s, r) {
    s.set("r", r);
    s.set("r2", r);
}

// ---- the host's view (apps/skystrike_zig_music.mjs) ----------------------
const dec = new TextDecoder();

/// The request pending for the host, if any: "name" or "name#tune".
function request(s) {
    const d = s.demo;
    if (!d.pollSongRequest()) return null;
    const name = dec.decode(new Uint8Array(s.memory.buffer, d.songNamePtr(), d.songNameLen()));
    return name.endsWith(".sndh") ? `${name}#${d.songTune()}` : name;
}

/// The run's request log: polled after every displayed frame, as the host
/// does: the song request, then the effect queue (sfx_queue.zig). s.take():
/// the requests since the last take, their zg.requestModVolume gains (x
/// 65536) as its .gains; s.takeSfx(): the queue's other commands.
export function track(s) {
    const got = [], gains = [], sfx = [];
    const poll = () => {
        const r = request(s);
        if (r) got.push(r);
        const n = s.demo.pollSfx(), dv = new DataView(s.memory.buffer, s.demo.sfxEntriesPtr(), n * 16);
        for (let i = 0; i < n; i++) {
            const o = i * 16, op = dv.getUint8(o);
            if (op === 4) gains.push(dv.getUint32(o + 8, true));
            else sfx.push({ op, a: dv.getUint8(o + 1), b: dv.getUint8(o + 2) });
        }
    };
    s.each = poll;
    s.take = () => { poll(); const r = got.splice(0); r.gains = gains.splice(0); return r; };
    s.takeSfx = () => { poll(); return sfx.splice(0); };
    return s;
}
