// screen.js of CODEF 295 (SWEDISH NEW YEAR DEMO), REPLAYED for the harness:
// go(), do_menu/do_omega and KeyCheck (SYNC and TCB are the disk's now), with
// the CODEF library calls they make (scrolltext_horizontal, FX sinx/siny,
// drawTile/drawPart with their clipping, midhandles and transforms), in f64 as
// JS runs them. The canvas is modelled at the port's documented sample points:
// ST pixel (X, Y) of the 640x450 work canvas is the 640-space pixel (2X, 2Y),
// every scaled or fractional draw nearest (pixel centre -> floor), and
// colour-0 rasters (the ST mechanism) under every drawn pixel.
// A frame is a gid per physical pixel (0 = colour 0) plus colour 0 per line.
import { at } from "./swedish_newyear_assets.mjs";

export const PW = 400, PH = 280, OX = 40, OY = 40;
const BLACK = 0xFF000000; // colours are the palette's RGBA, 0xAABBGGRR
const fl = Math.floor;

// scrolltext_horizontal (lib/codef_scrolltext.js), the parts this screen uses
class Scroll {
    constructor(text, fontw, canvasW, speed, sin) {
        this.text = text; this.fontw = fontw; this.speed = speed; this.sin = sin;
        this.wide = Math.ceil(canvasW / fontw) + 1;
        this.off = 0; this.letters = [];
        for (let i = 0; i <= this.wide; i++) {
            this.letters[i] = { posx: Math.ceil((this.wide * fontw) + i * fontw), ltr: text.charCodeAt(this.off) };
            this.off++;
        }
    }
    // draw()'s movement; returns [{posx, ltr, prov}] left to right
    draw() {
        let old = this.sin ? this.sin.myvalue : 0;
        for (const l of this.letters) {
            l.posx -= this.speed;
            if (l.posx <= -this.fontw) {
                l.posx = this.wide * this.fontw + (l.posx + this.fontw);
                if (this.sin) old += this.sin.inc;
                l.ltr = this.text.charCodeAt(this.off);
                this.off++;
                if (this.off > this.text.length - 1) this.off = 0;
            }
        }
        const out = [...this.letters].sort((a, b) => a.posx - b.posx).map((l) => ({ posx: l.posx, ltr: l.ltr, prov: 0 }));
        if (this.sin) {
            this.sin.myvalue = old;
            for (const o of out) { o.prov = Math.sin(this.sin.myvalue) * this.sin.amp; this.sin.myvalue += this.sin.inc; }
            this.sin.myvalue = old + this.sin.offset;
        }
        return out;
    }
    current() { return this.text.charCodeAt(this.off); }
}

export class Remake {
    constructor(A) {
        this.A = A; this.whichpart = 0; this.songs = [];
        this.menuscroll = new Scroll(A.text.menu, 95, 640, 10);
        // omega
        this.oldv = [0, 0, 0]; this.hv = [0, 0, 0];
        // omega
        this.oframe = 0; this.logosiny = 0;
        this.oscroll = new Scroll(A.text.omega, 30.7, 640, 6);
        this.song("scout");
    }
    song(t) { this.songs.push(t); }
    // Back to the menu. The remake's menu scroller kept its place; the real demo
    // reloads the menu from the disk after every part, so it starts over (the
    // port follows the disk here).
    toMenu() {
        this.whichpart = 0; this.song("scout");
        this.menuscroll = new Scroll(this.A.text.menu, 95, 640, 10);
    }

    // KeyCheck: 32 Space, 112..116 F1..F5 (as keyCodes)
    key(code) {
        if (code === 32) {
            if (this.whichpart >= 4) this.toMenu();
            if (this.whichpart === 3) this.whichpart = 4;
            if (this.whichpart === 2) this.toMenu();
            if (this.whichpart === 1) this.whichpart = 2;
        }
        const f = code - 112;
        if (f < 0 || f > 4) return;
        if (this.whichpart !== 0) return;
        if (f === 0) { this.whichpart = 1; this.song("jinx1"); }
        if (f === 1) this.whichpart = 3;
        if (f === 2) { this.whichpart = 5; this.song("icepalace"); }
    }

    // One host tick: go().
    frame(dt, regs) {
        this.g = new Int32Array(PW * PH); // gid 0 = colour 0 everywhere
        this.c0 = new Array(PH).fill(BLACK);
        const part = this.whichpart;
        [() => this.menu(), () => this.sync1(), () => this.sync2(), () => this.tcb1(), () => this.tcb2(), () => this.omega(regs)][part]();
        return { part, g: this.g, c0: this.c0 };
    }
    put(x, y, gid) { // work-canvas ST coordinates
        const X = x + OX, Y = y + OY;
        if (X >= 0 && Y >= 0 && X < PW && Y < PH && gid >= 0) this.g[Y * PW + X] = gid;
    }

    menu() {
        const A = this.A;
        for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) this.put(x, y, A.mainLut[y][A.mainPx[y * 320 + x]]);
        for (const l of this.menuscroll.draw()) { // drawTile(font7, ltr-32, posx, 397)
            const nb = l.ltr - 32, partx = (nb % 10) * 95, party = fl(nb / 10) * 55;
            if (Math.min(55, 330 - party) <= 0) continue;
            for (let y = 199; y < 225; y++) for (let x = 0; x < 320; x++) {
                const u = 2 * x - l.posx, v = 2 * y - 397;
                if (u < 0 || u >= 95 || v < 0 || v >= 55) continue;
                // font7.raw keeps each cell's odd rows: cell row k*27 + (v-1)/2
                this.put(x, y, at(A.img.font7, partx + u, fl(nb / 10) * 27 + (v - 1) / 2));
            }
        }
        for (const bx of [0, 608]) for (let y = 200; y < 225; y++) for (let x = bx / 2; x < bx / 2 + 16; x++) this.put(x, y, at(A.img.block, x - bx / 2, y - 200));
    }

    // SYNC #1 and #2 are ported from the disk and checked against the real
    // demo (sync_expect.py hashes), not against the remake: nothing to replay.
    sync1() {}

    watch(regs) {
        for (let c = 0; c < 3; c++) {
            const v = regs[8 + c] & 31;
            if (this.oldv[c] !== v) this.hv[c] = 7; else if (this.hv[c]-- < 1) this.hv[c] = 0;
        }
    }
    remember(regs) { for (let c = 0; c < 3; c++) this.oldv[c] = regs[8 + c] & 31; }

    sync2() {}

    // SYNC and TCB are ported from the disk and checked against the real demo
    // (the *_expect.py hashes), not against the remake: nothing to replay.
    tcb1() {}

    tcb2() {}

    omega(regs) {
        const A = this.A;
        this.watch(regs);
        for (let y = 0; y < 225; y++) for (let x = 0; x < 320; x++) {
            const u = 2 * x - 40, v = 2 * y - 40; // omain at (40,40), halved
            if (u >= 0 && u < 538 && v >= 0 && v < 255) this.put(x, y, at(A.img.omain, u / 2, v / 2));
            this.put(x, y, at(A.img.omega, 2 * x - 295, 2 * y - 345));
        }
        const cells = 307 / 30.7;
        for (const l of this.oscroll.draw()) { // drawTile(ofont, ltr-32, posx, 300): fractional cells
            const nb = l.ltr - 32, partx = fl(nb % cells) * 30.7, party = fl(nb / cells) * 28;
            const partw = Math.min(30.7, 307 - partx), parth = Math.min(28, 168 - party);
            if (partw <= 0 || parth <= 0) continue;
            for (let y = 150; y < 164; y++) for (let x = 0; x < 320; x++) {
                const lx = 2 * x + 0.5 - l.posx, r = 2 * y - 300;
                if (lx >= 0 && lx < partw && r < parth) this.put(x, y, at(A.img.ofont, fl(partx + lx), fl(party + r)));
            }
        }
        for (let y = 150; y < 175; y++) for (let x = 0; x < 320; x++) if (2 * x < 43 || 2 * x >= 576) this.put(x, y, 0);
        [341, 353, 365].forEach((row0, c) => {
            const t = fl((this.hv[c] / 7) * 14);
            for (let y = 0; y < 225; y++) for (let x = 0; x < 320; x++) {
                const r = 2 * y - row0;
                if (r < 0 || r >= 11) continue;
                const m = fl(-(2 * x + 0.5 - 293)); // scale(-1, 1) at 293
                if (m >= 0 && m < 198) this.put(x, y, at(A.img.vumeter, m / 2, t * 11 + r));
                const n = 2 * x - 324;
                if (n >= 0 && n < 198) this.put(x, y, at(A.img.vumeter, n / 2, t * 11 + r));
            }
        });
        this.remember(regs);
        this.logosiny += 0.06;
        const nb = this.oframe, partx = fl(nb % 4) * 172, party = fl(nb / 4) * 134;
        const top = 184 - Math.abs(Math.sin(this.logosiny) * 47) - 67;
        for (let y = 0; y < 225; y++) for (let x = 0; x < 320; x++) {
            const u = 2 * x - 229, v = fl(2 * y + 0.5 - top);
            if (u >= 0 && u < 172 && v >= 0 && v < 134) this.put(x, y, at(A.img.atari, (partx + u - 1) / 2, party + v));
        }
        this.oframe += 0.5;
        if (this.oframe >= 31) this.oframe = 0;
    }
}
