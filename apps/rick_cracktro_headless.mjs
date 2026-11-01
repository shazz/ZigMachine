// Headless check of RICK DANGEROUS's front: The Empire's CABAL cracktro
// (EMP_CABL.PRG), patched as the game's trainer menu
// (apps/zig/scenes/rick_dangerous/cracktro.zig).
//   original  the typewriter fed the ORIGINAL text: at the four text positions
//             Hatari froze the original at (apps/rick_cracktro_fixture.json.gz,
//             tools/rick_dangerous/make_cracktro_fixture.py) the plane is the
//             original's screen pixel for pixel, reached in the original's VBLs
//   rick      the patched text: page 1 is the original's but for its line 1
//             (RICK DANGEROUS for CABAL); the tune is Leavin Teramis subtune
//             11 (matched against the original running in Hatari); Space
//             stops it and asks the three questions; the cursor blinks every
//             30 VBLs while it waits; y / n / Y set the flags, others nothing;
//             the third answer starts the game (its title tune); a key held
//             through the cracktro never reaches the game; Escape leaves
//   trainer   each flag stops its decrement (apps/rick_cracktro_trainer.mjs)
//   node apps/rick_cracktro_headless.mjs [outdir]
//   --break trainer   the flags not set: the trainer check catches it
//   --break text      the patched text against the original's screens: caught
//   --break timing    the typing restarted after the first screen: the VBL check catches it
import { mkdir, readFile } from "node:fs/promises";
import { gunzipSync } from "node:zlib";
import { boot, shownInk, inkDiff, shot, fnv, runTo } from "./rick_cracktro_lib.mjs";
import { trainerCheck } from "./rick_cracktro_trainer.mjs";

const BREAKS = { trainer: "trainer:", text: "pixels differ", timing: " at VBL " };
const bi = process.argv.indexOf("--break");
const broke = bi > 0 ? process.argv[bi + 1] : null;
if (broke && !(broke in BREAKS)) throw new Error(`--break ${Object.keys(BREAKS).join(" | ")}`);
const outdir = process.argv.slice(2).find((a, i, v) => !a.startsWith("--") && v[i - 1] !== "--break") || "/tmp/rick_cracktro";
const refs = JSON.parse(gunzipSync(await readFile("apps/rick_cracktro_fixture.json.gz"))).refs;
const MUSIC = "leavin_teramis.sndh#11";
const TITLE_TUNE = "rick_dangerous.sndh#64"; // the title, id 5 (rick_dangerous_headless.mjs)
const KEY = 0x38cae; // the game's ACIA key byte (keys.zig)
const RICK_SHIFT = "RICK DANGEROUS".length - "CABAL".length;
/// The trainer's first question (ESC E "Infinite lives y/n:"), cursor shown.
const PROMPT_HASH = "888089d1";

async function original() {
    const ctx = await boot();
    const errors = [];
    ctx.demo.rickCrackRestart(broke === "text" ? 0 : 1);
    let v0 = null;
    for (const r of refs) {
        const v = runTo(ctx, r.pos);
        if (v < 0) return [`original: never idle at text + $${r.pos.toString(16)}`];
        if (broke === "timing" && v0 === null) ctx.demo.rickCrackRestart(1); // lose the time typed so far
        v0 ??= v - r.vbl;
        if (v - r.vbl !== v0) errors.push(`original: text + $${r.pos.toString(16)} at VBL ${v - v0}, the original's ${r.vbl}`);
        const { ink, other } = shownInk(ctx);
        await shot(ink, `${outdir}/original_${r.name}.ppm`);
        const d = inkDiff(ink, Buffer.from(r.ink, "base64"));
        if (d.n || other) errors.push(`original: text + $${r.pos.toString(16)}: ${d.n} pixels differ from Hatari's (rows ${d.rows}), ${other} neither paper nor ink`);
    }
    console.log(`  original: ${refs.length} screens of the original text = Hatari's, pixel for pixel, at the original's VBLs`);
    return errors;
}

async function rick() {
    const ctx = await boot();
    const errors = [];
    const fail = (m) => errors.push(`rick: ${m}`);
    // page 1: the original's but for line 1
    const p1 = refs.find((r) => r.name === "p0df");
    if (runTo(ctx, p1.pos + RICK_SHIFT) < 0) return [`rick: never idle at the end of page 1`];
    if (ctx.songs.join() !== MUSIC) fail(`the song requests are [${ctx.songs}], not ${MUSIC} alone`);
    const page1 = shownInk(ctx).ink;
    await shot(page1, `${outdir}/rick_page1.ppm`);
    const d = inkDiff(page1, Buffer.from(p1.ink, "base64"));
    if (!d.n || d.rows.join() !== "1") fail(`page 1 differs from the original's in rows [${d.rows}] (${d.n} pixels), not row 1 alone`);
    // Space, held: the music stops, the first question
    ctx.demo.key(32);
    ctx.step(3);
    if (ctx.val(0) !== 1) fail(`Space: phase ${ctx.val(0)}, not the trainer`);
    if (ctx.songs.at(-1) !== "none") fail(`Space did not stop the music (${ctx.songs})`);
    const border = () => new Uint32Array(ctx.memory.buffer, ctx.machine.hwPhysicalPtr(), 800 * 280)[10 * 800 + 10] & 0xffffff;
    if (border() !== 0xffffff) fail(`the cracktro's border is $${border().toString(16)}, not colour 0 (white)`);
    const prompt = shownInk(ctx).ink;
    await shot(prompt, `${outdir}/rick_trainer.ppm`);
    if (fnv(prompt) !== PROMPT_HASH) fail(`the trainer prompt's hash is ${fnv(prompt)}, pinned ${PROMPT_HASH}`);
    // the cursor: 30 VBLs on, 30 off, 30 on
    const flips = [];
    for (let i = 0, was = ctx.val(6); i < 100; i++) {
        ctx.step();
        if (ctx.val(6) !== was) { was = ctx.val(6); flips.push(ctx.val(5)); }
    }
    if (flips.length < 3 || flips[1] - flips[0] !== 30 || flips[2] - flips[1] !== 30) fail(`the cursor flipped at VBLs ${flips}, not every 30`);
    for (const cp of [0x78, 0x79, 0x6e, 0x59]) { ctx.demo.key(cp); ctx.step(2); ctx.demo.keyUp(cp); ctx.step(2); } // x (nothing), y, n, Y
    if (ctx.val(4) !== 5) fail(`x y n Y set the trainer to ${ctx.val(4)}, not 5 (lives, dynamite)`);
    if (ctx.val(0) !== 2) fail(`after the third answer: phase ${ctx.val(0)}, not the game`);
    ctx.step(250);
    if (border() !== 0) fail(`the game's border is $${border().toString(16)}, not black`);
    if (!ctx.songs.includes(TITLE_TUNE)) fail(`no title tune after the cracktro (${ctx.songs})`);
    ctx.demo.keyUp(32); // Space, held since the cracktro, released in the game
    ctx.step(2);
    const key = new Uint8Array(ctx.memory.buffer, ctx.demo.rickTestMemPtr(), 0x80000)[KEY];
    if (key === 0xb9) fail("the game heard Space's release, pressed in the cracktro");
    await shot(shownInk(ctx).ink, `${outdir}/rick_game.ppm`);
    // Escape in the cracktro leaves the cart
    const esc = await boot();
    esc.step(50);
    esc.demo.key(0xe012);
    esc.step(1);
    if (esc.demo.pollCartRequest() !== -1) fail("Escape in the cracktro did not leave for the menu");
    console.log(`  rick: page 1 = the original's but line 1, ${MUSIC} then silence on Space, the prompt, ` +
        `the cursor every 30 VBLs, y/n/Y -> mask ${ctx.val(4)}, the game and its tune, Space's release swallowed, Escape leaves`);
    return errors;
}

await mkdir(outdir, { recursive: true });
let errors = [];
if (broke === "trainer") errors = await trainerCheck(await boot(), () => 0);
else if (broke) errors = await original();
else errors = [...await original(), ...await rick(), ...await trainerCheck(await boot(), (b) => b)];
if (broke) {
    const hit = errors.find((e) => e.includes(BREAKS[broke]));
    console.log(hit ? `rick_cracktro: PASS (--break ${broke} caught: ${hit})` :
        `rick_cracktro: FAILED -- --break ${broke} was not caught (${errors.length} other errors: ${errors})`);
    process.exit(hit ? 0 : 1);
}
console.log(errors.length ? `rick_cracktro: FAILED -- ${errors.join("; ")}` : "rick_cracktro: all pass");
process.exit(errors.length ? 1 : 0);
