// Headless RNO / SODIUM driver — boots the sealed machine the way
// docs/sealed-loader.js does, steps the intro one 50 Hz VBL per host frame
// (dt = 20 ms) and checks it against the REAL THING:
//   snapshots  at the eight counter values the Hatari RAM snapshots were taken
//              at (one per effect: wobble, curtain, text, prism, distorter...),
//              the 320x200 frame on screen is the snapshot's displayed ST
//              screen through the part's palette, pixel for pixel (FNV-1a of
//              the RGB, computed offline from the snapshots). The check is
//              proved to discriminate: the frame one VBL early must NOT match.
//   timeline   PO·RNO until C = 384, the eye picture from C = 385
//   pacing     at a 60 Hz host the counter still runs at 50 Hz (elapsed time),
//              so part 2 starts after 7.7 s, not after 385 frames
//   music      gritty.sndh is requested at start, and again when the intro
//              loops after C = 4656
//   node apps/rno_sodium_headless.mjs [outdir]
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { cartRam, romRam } from "../docs/wasm_hiwater.js";

const PAGES = 112; // must match SHARED_PAGES in machine/sdk/memmap.zig
const PLANES = 1; // one plane: the ST showed one screen
const CART = "docs/demo-rno_sodium.wasm";
const MUSIC = "gritty.sndh";
const END = 4656; // the last part's limit, cmpi.l #$1230

// C -> FNV-1a of the 320x200 RGB frame, from the Hatari RAM snapshots of the
// original (the ST screen the video base register points at, 3-bit guns
// scaled by 255/7 and truncated, as rno_sodium/st.zig's stColor does).
const SNAPSHOTS = [
    [159, 0xe1758495, "PO·RNO wobble, 4-plane ghost trail"],
    [489, 0x76b190bf, "eye + curtain"],
    [739, 0xf1defd18, "text page 1 over the curtain"],
    [1642, 0xa7cde861, "prism (back buffer, double-buffered)"],
    [2092, 0x0b0acf1f, "curtain, second pass"],
    [2342, 0x42094a9b, "text page 2 over the curtain"],
    [2892, 0xbc38a710, "distorter (back buffer, double-buffered)"],
    [3592, 0x8bcc5397, "curtain, third pass"],
];

async function boot() {
    const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
    const dec = new TextDecoder();
    let demo;
    const machine = (await WebAssembly.instantiate(await readFile("docs/machine-video.wasm"), {
        env: { memory, hblDispatch: (id, p, l, x) => demo.hblDispatch(id, p, l, x) },
    })).instance.exports;
    const romBytes = await readFile("docs/rom.wasm");
    const env0 = { memory, hwVideoBase: machine.hwVideoBase, hwBlit: machine.hwBlit };
    const rom = (await WebAssembly.instantiate(romBytes, { env: env0 })).instance.exports;
    machine.hwSetRomHigh(romRam(romBytes).high ?? 0);
    const noop = () => {};
    const cartBytes = await readFile(CART);
    demo = (await WebAssembly.instantiate(cartBytes, {
        env: {
            ...env0,
            jsConsoleLogWrite: noop, jsConsoleLogFlush: noop, jsThrowError: noop,
            consoleLogJS: (p, l) => console.log("[wasm]", dec.decode(new Uint8Array(memory.buffer, p, l))),
            hwRamBase: machine.hwRamBase, hwRamTop: machine.hwRamTop, hwRamSize: machine.hwRamSize,
            hwRamUsed: machine.hwRamUsed, hwRamFree: machine.hwRamFree,
            hwRamAlloc: machine.hwRamAlloc, hwRamMark: machine.hwRamMark,
            hwRamRelease: machine.hwRamRelease, hwRamAllocFailures: machine.hwRamAllocFailures,
            hwRomRamBase: machine.hwRomRamBase, hwRomRamTop: machine.hwRomRamTop,
            hwRomRamSize: machine.hwRomRamSize, hwRomRamUsed: machine.hwRomRamUsed,
            hwRomRamFree: machine.hwRomRamFree, ...rom,
            audioPlay: noop, audioStop: noop, loadSample: noop, beep: noop, diskReadBlock: noop,
            hostAudioStreamStart: noop, hostAudioFeed: noop, hostAudioStreamStop: noop,
        },
    })).instance.exports;
    machine.hwSetCartHigh(cartRam(cartBytes).high ?? 0);
    machine.hwInit();
    demo.boot();
    demo.skipBoot();
    return new Screen(memory, machine, demo, dec);
}

class Screen {
    constructor(memory, machine, demo, dec) {
        Object.assign(this, { memory, machine, demo, dec });
        this.w = machine.hwPhysWidth(); // 800: the 320x200 window is x-DOUBLED at (80, 40)
        this.pfb = new Uint8Array(memory.buffer, machine.hwPhysicalPtr(), this.w * machine.hwPhysHeight() * 4);
        this.frames = 0;
        this.songs = []; // [frame, name]
        this.rgb = null;
    }

    // Host frames, as docs/sealed-loader.js sequences them.
    run(n, dt = 20) {
        for (let i = 0; i < n; i++, this.frames++) {
            this.machine.hwClear();
            this.demo.frame(dt);
            if (this.demo.pollSongRequest()) {
                const name = this.dec.decode(new Uint8Array(this.memory.buffer, this.demo.songNamePtr(), this.demo.songNameLen()));
                this.songs.push([this.frames + 1, name]);
            }
            for (let p = 0; p < PLANES; p++) this.machine.hwRenderPlane(p);
        }
        this.rgb = this.visible();
    }

    // The 320x200 visible window, un-doubled, 3 bytes a pixel.
    visible() {
        const out = new Uint8Array(320 * 200 * 3);
        for (let y = 0; y < 200; y++) {
            for (let x = 0; x < 320; x++) {
                const i = ((40 + y) * this.w + 80 + x * 2) * 4;
                const a = this.pfb[i + 3] / 255;
                for (let c = 0; c < 3; c++) out[(y * 320 + x) * 3 + c] = Math.round(this.pfb[i + c] * a);
            }
        }
        return out;
    }

    px(x, y) {
        const o = (y * 320 + x) * 3;
        return [this.rgb[o], this.rgb[o + 1], this.rgb[o + 2]];
    }
    async shot(path) {
        const hdr = new TextEncoder().encode("P6\n320 200\n255\n");
        await writeFile(path, Buffer.concat([hdr, this.rgb]));
        console.log(`  shot: ${path} (C = ${this.frames})`);
    }
}

function fnv(bytes) {
    let h = 0x811c9dc5;
    for (const b of bytes) h = Math.imul(h ^ b, 0x01000193) >>> 0;
    return h;
}
const hex = (h) => "0x" + h.toString(16).padStart(8, "0");

async function checkSnapshots(s, out) {
    for (const [c, want, what] of SNAPSHOTS) {
        s.run(c - 1 - s.frames);
        const early = fnv(s.rgb); // one VBL before the snapshot
        s.run(1);
        const got = fnv(s.rgb);
        if (got !== want) {
            await s.shot(`${out}/mismatch-${c}.ppm`);
            throw new Error(`C=${c} (${what}): frame ${hex(got)}, the Hatari snapshot is ${hex(want)}`);
        }
        if (early === want) throw new Error(`C=${c}: the frame one VBL earlier matches too, so the check proves nothing`);
        console.log(`  snapshot C=${c}: ${what} — identical to the original`);
        await s.shot(`${out}/C${c}.ppm`);
    }
}

// Part 1 leaves px 0..31 white; part 2 copies the eye picture over it.
function leftIsWhite(s) {
    for (let y = 0; y < 200; y++) for (let x = 0; x < 32; x++) if (s.px(x, y).some((c) => c !== 255)) return false;
    return true;
}

async function checkTimelineAndPacing() {
    const a = await boot();
    a.run(384);
    if (!leftIsWhite(a)) throw new Error("C=384: the wobble part should still be up");
    a.run(1);
    if (leftIsWhite(a)) throw new Error("C=385: the eye picture should be up");
    console.log("  timeline: PO·RNO through C=384, the eye picture at C=385");

    const b = await boot(); // a 60 Hz host
    b.run(455, 1000 / 60); // 7.58 s: C = 379
    if (!leftIsWhite(b)) throw new Error("60 Hz host, 7.58 s: part 2 already started — the counter runs at the host's rate");
    b.run(15, 1000 / 60); // 7.83 s: C = 391
    if (leftIsWhite(b)) throw new Error("60 Hz host, 7.83 s: part 2 has not started");
    console.log("  pacing: at 60 Hz the counter still runs at 50 Hz (part 2 at 7.7 s, not at frame 385)");
}

function checkMusic(s) {
    const first = s.songs[0];
    if (!first || first[1] !== MUSIC || first[0] !== 1) throw new Error(`no ${MUSIC} request on the first frame: ${JSON.stringify(s.songs)}`);
    const again = s.songs.find(([f, n]) => f > 1 && n === MUSIC);
    if (!again || again[0] !== END + 1) throw new Error(`the loop did not restart ${MUSIC} at C=${END + 1}: ${JSON.stringify(s.songs)}`);
    if (s.songs.length !== 2) throw new Error(`unexpected song requests: ${JSON.stringify(s.songs)}`);
    console.log(`  music: ${MUSIC} requested at start and again when the intro loops (frame ${again[0]})`);
}

const out = process.argv[2] || "/tmp/rno_sodium";
await mkdir(out, { recursive: true });
const screen = await boot();
await checkSnapshots(screen, out);
await checkTimelineAndPacing();

const t0 = performance.now();
const before = screen.frames;
screen.run(END + 10 - screen.frames); // through the end, the loop and part 1 again
checkMusic(screen);
if (!leftIsWhite(screen)) throw new Error("after the loop: PO·RNO should be back");
console.log(`  soak: ${screen.frames} VBLs clean, ${((performance.now() - t0) / (screen.frames - before)).toFixed(3)} ms/frame ` +
    "(update + render + 1 plane composite + the harness's own readback)");
