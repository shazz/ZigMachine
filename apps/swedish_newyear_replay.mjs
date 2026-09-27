// screen.js of CODEF 295 (SWEDISH NEW YEAR DEMO), REPLAYED for the harness:
// go(), do_menu and KeyCheck (SYNC, TCB and OMEGA are the disk's now), with
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
    frame() {
        this.g = new Int32Array(PW * PH); // gid 0 = colour 0 everywhere
        this.c0 = new Array(PH).fill(BLACK);
        const part = this.whichpart;
        [() => this.menu(), () => this.sync1(), () => this.sync2(), () => this.tcb1(), () => this.tcb2(), () => this.omega()][part]();
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

    sync2() {}

    // SYNC, TCB and OMEGA are ported from the disk and checked against the real
    // demo (the *_expect.py hashes), not against the remake: nothing to replay.
    tcb1() {}

    tcb2() {}

    omega() {}
}
