// SKYSTRIKE's ZIG mode (cart 79; apps/zig/scenes/skystrike/zig_*.zig), headless.
// ORIGINAL is the ST's and apps/skystrike_headless.mjs proves it; this proves
// what ZIG adds and that it adds nothing to the game itself:
//   (a) crossings left, right, up and down: no redraw pause, a frame every VBL,
//       the camera gliding with the plane            apps/skystrike_zig_flight.mjs
//   (b) the ring's slot of each screen entered = the game's own draw of it
//   (c) switched by Z mid-flight, or ZIG throughout, the logic state after
//       every pass = ORIGINAL's                      apps/skystrike_zig_crc.mjs
//   (d) the fullscreen frame: borders open, = ring + overlay everywhere, the
//       HUD in the borders; the tracers; the ammo    apps/skystrike_zig_view.mjs
//   (e) no zg.mem allocation refused
//   sound  each event's sample on a Paula channel, the music on the YM
//       untouched, none in ORIGINAL                  apps/skystrike_zig_sound.mjs
//   pause  P: the key help over ZIG's pause, not ORIGINAL's; the CRC the same
//       before, during, after                        apps/skystrike_zig_pause.mjs
//   node apps/skystrike_zig.mjs [outdir]            (screenshots in outdir)
//   node apps/skystrike_zig.mjs --break pause|ring|crc|border|alloc|sound|tracer|help
//       flown in ORIGINAL / a ring pixel flipped / X for Z / ORIGINAL's frame /
//       a refused allocation / the sample table swapped / the heading turned /
//       ORIGINAL's pause searched for the panel: passes only if caught by the
//       check it breaks
import { mkdir } from "node:fs/promises";
import { flight } from "./skystrike_zig_flight.mjs";
import { crc } from "./skystrike_zig_crc.mjs";
import { view } from "./skystrike_zig_view.mjs";
import { sound } from "./skystrike_zig_sound.mjs";
import { pause } from "./skystrike_zig_pause.mjs";

const BREAKS = ["pause", "ring", "crc", "border", "alloc", "sound", "tracer", "help"];
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (bi > 0 && !BREAKS.includes(broke)) throw new Error(`--break ${BREAKS.join(" | ")}`);
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/skystrike_zig";
await mkdir(outdir, { recursive: true });

/// (e): the sessions' cart RAM, and the sandbox's silence.
function allocations(sessions, errors) {
    for (const s of sessions) {
        const refused = s.machine.hwRamAllocFailures() || s.val(5);
        if (refused) errors.push(`(e) ${refused} zg.mem allocation(s) refused`);
    }
    console.log(`  (e) ${sessions.length} sessions: no zg.mem allocation refused`);
}

const errors = [];
const run = async (f) => { const r = await f(); errors.push(...(r.errors ?? r)); return r; };
const fl = await run(() => flight(broke));
await run(() => crc(broke));
const vw = await run(() => view(outdir, broke));
await run(() => sound(broke));
await run(() => pause(outdir, broke));
if (broke === "alloc") vw.s.demo.skyTestRefuse();
allocations([fl.s, vw.s], errors);
if (broke) {
    // caught by the check it breaks, not by some other one
    const by = { pause: "(a)", ring: "(b)", crc: "(c)", border: "(d)", alloc: "(e)", sound: "sound:", tracer: "tracers:", help: "pause:" }[broke];
    const hit = errors.find((e) => e.startsWith(by));
    console.log(hit ? `skystrike_zig: PASS (--break ${broke} caught: ${hit})` : `skystrike_zig: FAILED -- --break ${broke} was not caught by ${by} (${errors.length} other errors)`);
    process.exit(hit ? 0 : 1);
}
console.log(errors.length ? `skystrike_zig: FAILED -- ${errors.join("; ")}` : "skystrike_zig: all pass");
process.exit(errors.length ? 1 : 0);
