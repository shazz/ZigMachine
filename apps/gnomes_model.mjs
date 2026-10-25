// The ORIGINAL "BB25" screen as a model, for apps/gnomes_headless.mjs. Written from the
// disassembly of the running intro (RAM addresses; prototypes/gnomes_re/ram_code.dis) and the
// ripped assets, NOT from the Zig: an ST screen of colour indices 0..15 plus the ST's own
// palette per line (colours 0/1 from the 276-line Timer-B list, regs 2..7 split three ways).
// image() lays it out the port's way (ST x -> plane x + 40, line L -> row L + 2) as ST words.
import { readFile } from "node:fs/promises";

const A = "apps/zig/assets/screens/gnomes/";
const u16s = (b) => Array.from({ length: b.length / 2 }, (_, i) => b.readUInt16LE(2 * i));

export async function loadAssets() {
    const r = (f) => readFile(A + f);
    const src = await readFile("apps/zig/scenes/gnomes/text.zig", "utf8");
    const big = JSON.parse(`"${src.match(/pub const BIG_TEXT = "((?:[^"\\]|\\.)*)";/)[1]}"`);
    return {
        bg: u16s(await r("bg.bin")), barPos: u16s(await r("barpos.bin")), barCol: u16s(await r("barcol.bin")),
        col1: u16s(await r("col1.bin")), dx: u16s(await r("logo_dx.bin")).map((w) => (w << 16) >> 16),
        logo: await r("logo.raw"), sbob: await r("sbob.raw"), font8: await r("font8.bin"),
        font32: await r("font32.raw"), map32: await r("font32_map.bin"), tty: await r("tty.bin"), big,
    };
}

const LOGO_PAL = [0x760, 0x750, 0x740, 0x730, 0x720, 0x710]; // $14084: regs 2..7 at VBL (the movem at $13D30 reads $14080)
const SBOB_PAL = [0x003, 0x020, 0x774, 0x553, 0x332, 0x321, 0x210, 0x666, 0x777, 0x755, 0x701, 0x622, 0x356, 0x377, 0x555, 0x000]; // $10A5A
const SCROLL_PAL = [0x764, 0x653, 0x542, 0x431, 0x320, 0x210]; // $14064: regs 2..7 from the bottom border
export const SPLIT_SB = 50; // $13E46 (Timer A, ~line 50): no colour 2..7 pixel between 36 and 80
export const SPLIT = 230; // $13EAA: no colour 2..7 pixel on 229..234 either side
export const W = 320, LINES = 276, PW = 400, PH = 280, X0 = 40, Y0 = 2;

export class Original {
    constructor(a, brk = null) {
        this.a = a;
        this.brk = brk;
        this.scr = new Uint8Array(W * LINES);
        this.ptr = 0; this.col = 0; this.row = 10; this.pause = 0; this.page = 0;
        this.typed = []; // [n, col, row, catch-up n] of every glyph, for the harness's race mask
        for (let y = 0; y < 158; y++) for (let x = 0; x < 144; x++) this.scr[(80 + y) * W + 176 + x] = a.sbob[y * 144 + x];
    }

    // Loop n ($13974): the TTY's one action, then the screen as loop n leaves it.
    step(n, ym) {
        this.tty(n);
        this.vu(ym);
        this.logo(this.brk === "sweep" ? n - 1 : n - 2); // the beam shows the frame-before-last's copy
        this.scroller(this.brk === "scroll" ? n + 1 : n);
    }

    tty(n) {
        const t = this.a.tty;
        if (this.pause) {
            if (--this.pause < 2) {
                if (this.pause === 1) for (let y = 80; y < 200; y++) this.scr.fill(0, y * W, y * W + 176);
                this.col = 0; this.row = 10;
                if (t[this.ptr] === 0) { this.ptr = 0; this.page = 0; }
            }
            return;
        }
        let ch = t[this.ptr++];
        if (this.brk === "page" && this.page === 1 && ch > 32) ch = 0x58; // page 2 in X's
        if (ch === 0) { this.pause = 250; this.page++; }
        else if (ch === 13) this.col = 0;
        else if (ch === 10) this.row++;
        else {
            for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++)
                this.scr[(this.row * 8 + y) * W + this.col * 8 + x] = this.a.font8[ch * 64 + y * 8 + x];
            // The original draws each glyph into the buffer of loop n, and into the other buffer
            // at the next glyph's loop (the "previous character" redraw, $13C82).
            if (this.typed.length) this.typed[this.typed.length - 1][3] = n;
            this.typed.push([n, this.col, this.row, Infinity]);
            this.col++;
        }
    }

    vu(ym) {
        const regs = this.brk === "vu" ? [8, 9, 10] : [10, 9, 8];
        for (let b = 0; b < 3; b++) for (let r = 0; r < 16; r++) {
            const lit = 15 - r <= ym[regs[b]] ? 1 : 0;
            this.scr.fill(lit, (42 + 2 * r) * W + 48 + 80 * b, (42 + 2 * r) * W + 112 + 80 * b);
        }
    }

    logo(f) {
        for (let r = 0; r < 36; r++) {
            const x0 = 16 + this.a.dx[(Math.max(f, 0) + r) % 2816];
            for (let x = 0; x < W; x++) {
                const lx = x - x0;
                this.scr[r * W + x] = lx >= 0 && lx < 288 ? this.a.logo[r * 288 + lx] : 0;
            }
        }
    }

    scroller(n) {
        for (let j = 0; j < 40; j++) {
            const k = n - 39 + j;
            const g = k < 4 ? 0 : this.a.map32[this.a.big.charCodeAt((Math.floor(k / 4) - 1) % this.a.big.length) - 32];
            const c = ((k % 4) + 4) % 4;
            for (let y = 0; y < 25; y++) for (let x = 0; x < 8; x++)
                this.scr[(251 + y) * W + j * 8 + x] = this.a.font32[(g * 25 + y) * 32 + c * 8 + x];
        }
    }

    // Colour 0 of every line in frame n: the list loop n-1 built ($139DC), black in frame 1.
    colour0(n) {
        const c0 = new Array(LINES).fill(0);
        if (n <= 1) return c0;
        const c = (n - 1 + (this.brk === "raster" ? 1 : 0)) & 511;
        for (let l = 0; l < LINES; l++) c0[l] = this.a.bg[(c & 127) + l];
        let s = 0;
        for (let i = 0; i < 16; i++) {
            let l = this.a.barPos[(c + 3 * i) & 511];
            for (let k = 0; k < 15; k++) { c0[l] = this.a.barCol[s++]; if (++l >= LINES) break; }
            if (s === 90) s = 0;
        }
        return c0;
    }

    // The frame as the port's plane shows it: ST words, PW x PH.
    image(n) {
        const c0 = this.colour0(n), out = new Uint16Array(PW * PH);
        for (let l = 0; l < LINES; l++) {
            const pal = [c0[l], this.a.col1[l], ...(l < SPLIT_SB ? LOGO_PAL : l < SPLIT ? SBOB_PAL.slice(2, 8) : SCROLL_PAL), ...SBOB_PAL.slice(8)];
            const row = (l + Y0) * PW;
            out.fill(c0[l], row, row + PW);
            for (let x = 0; x < W; x++) out[row + X0 + x] = pal[this.scr[l * W + x]];
        }
        return out;
    }
}
