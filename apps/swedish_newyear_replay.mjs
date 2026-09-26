// screen.js of CODEF 295 (SWEDISH NEW YEAR DEMO), REPLAYED for the harness:
// go(), do_menu/do_sync1/do_sync2/do_tcb1/do_tcb2/do_omega and KeyCheck, with
// the CODEF library calls they make (scrolltext_horizontal, FX sinx/siny,
// drawTile/drawPart with their clipping, midhandles and transforms), in f64 as
// JS runs them. The canvas is modelled at the port's documented sample points:
// ST pixel (X, Y) of the 640x450 work canvas is the 640-space pixel (2X, 2Y),
// every scaled or fractional draw nearest (pixel centre -> floor), and
// colour-0 rasters (the ST mechanism) under every drawn pixel.
// A frame is a gid per physical pixel (0 = colour 0) plus colour 0 per line.
import { at, localAt } from "./swedish_newyear_assets.mjs";

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

// FX: the per-line shifts of one sinx/siny call, then value = old + offset
function fxRun(params, n) {
    const old = params.map((p) => p.value), out = new Float64Array(n);
    for (let i = 0; i < n; i++) {
        let prov = 0;
        for (const p of params) prov += Math.sin(p.value) * p.amp;
        out[i] = prov;
        for (const p of params) p.value += p.inc;
    }
    params.forEach((p, j) => { p.value = old[j] + p.offset; });
    return out;
}
const P = (value, amp, inc, offset) => ({ value, amp, inc, offset });

export class Remake {
    constructor(A) {
        this.A = A; this.whichpart = 0; this.songs = [];
        this.menuscroll = new Scroll(A.text.menu, 95, 640, 10);
        // sync 1
        this.y1 = 100; this.XX = 1; this.size = 0.05; this.tile = 0; this.flip = 1; this.flipinc = -0.5;
        this.bounce = 0; this.bounceinc = 2; this.fx = 0;
        this.myscroll = new Scroll(A.text.sync1, 32, 520, 4, { myvalue: 0, amp: 45, inc: 0.6, offset: 0.08 });
        this.myscroll2 = new Scroll(A.text.sync1, 32, 520, 4);
        this.fx1 = [P(0, -20, 0.03, -0.05), P(0, 10, 0.01, 0.08)];
        this.fx2 = [P(0, 10, 0.03, -0.05), P(0, 10, 0.01, 0.08)];
        // sync 2 / omega
        this.oldv = [0, 0, 0]; this.hv = [0, 0, 0];
        // tcb 1
        this.musicplease = 0; this.n = 0; this.introOn = false; this.introMs = 0;
        this.tcbfx = [P(0, 1, 0.2, -0.05), P(0, 15, 0.05, 0.005), P(0, 7, 0.1, 0.08)];
        this.noise = makeNoise();
        // tcb 2
        this.colour = 1; this.rota = 0; this.counter = 0; this.Y = 0; this.Yinc = 3; this.loop = 0;
        this.tcb2fx = 0; this.siny = 0;
        this.angles = [0, 1, 2, 3, 4].map((i) => 0.25 * i);
        this.t2scroll = new Scroll(A.text.tcb2, 48, 329, 5);
        this.t2scroll2 = new Scroll(A.text.tcb2_cylinder, 32, 704, 2);
        this.t2fx = [P(0, 10, 0.03, -0.06), P(0, 10, 0.01, 0.05)];
        this.t2fx2 = [P(0, 20, 0.02, -0.05), P(0, 10, 0.04, 0.008)];
        this.t2fx3 = [P(0, 60, 0.04, -0.05), P(0, 25, 0.06, 0.05)];
        // omega
        this.oframe = 0; this.logosiny = 0;
        this.oscroll = new Scroll(A.text.omega, 30.7, 640, 6);
        this.song("scout");
    }
    song(t) { this.songs.push(t); }

    // KeyCheck: 32 Space, 112..116 F1..F5 (as keyCodes)
    key(code) {
        if (code === 32) {
            if (this.whichpart >= 4) { this.whichpart = 0; this.song("scout"); }
            if (this.whichpart === 3) { this.introOn = false; this.song("dugger3"); this.whichpart = 4; }
            if (this.whichpart === 2) { this.whichpart = 0; this.song("scout"); }
            if (this.whichpart === 1) this.whichpart = 2;
        }
        const f = code - 112;
        if (f < 0 || f > 4) return;
        if (this.whichpart === 4) this.song(["dugger4", "dugger5", "dugger1", "dugger2", "dugger3"][f]);
        if (this.whichpart !== 0) return;
        if (f === 0) { this.whichpart = 1; this.song("jinx1"); }
        if (f === 1) { this.song("tcb_intro"); this.whichpart = 3; this.introOn = true; this.introMs = 0; }
        if (f === 2) { this.whichpart = 5; this.song("icepalace"); }
    }

    // One host tick: Howl's onend between frames, then go().
    frame(dt, regs) {
        if (this.whichpart === 3 && this.introOn) {
            this.introMs += dt;
            if (this.introMs >= 13143) { this.introOn = false; this.musicplease = 1; }
        }
        this.g = new Int32Array(PW * PH); // gid 0 = colour 0 everywhere
        this.c0 = new Array(PH).fill(BLACK);
        const part = this.whichpart;
        [() => this.menu(), () => this.sync1(), () => this.sync2(regs), () => this.tcb1(), () => this.tcb2(), () => this.omega(regs)][part]();
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

    sync1() {
        const A = this.A, d = 0.044;
        for (let y = 0; y < 225; y++) { // rasters, 5 red bars, white bar: colour 0
            const r = 2 * y;
            let c = BLACK;
            if (r >= 181 && r < 247) c = A.rasters_rows[r - 181];
            [[0.6, 0.5], [3.6, 0.6], [6.6, 0.7], [9.9, 0.8], [13.2, 1]].forEach(([k, h]) => {
                const yc = 150 - 130 * Math.sin(this.y1 + k * d), s = fl((r + 0.5 - yc) / h + 13);
                if (s >= 0 && s < 26) c = A.redraster_rows[s];
            });
            if (r >= 40 && r < 62) c = A.whiteraster_rows[r - 40];
            this.c0[y + OY] = c;
        }
        this.y1 += d;
        if (this.XX !== 0) for (let y = 0; y < 225; y++) { // banner.drawTile(tile, 320, 51, 1, 0, 1, XX)
            const v = fl((2 * y + 0.5 - 51) / this.XX + 35);
            if (v < 0 || v >= 70) continue;
            for (let x = 0; x < 320; x++) {
                const u = 2 * x - 187; // x + 0.5 - 320 + 133
                if (u >= 0 && u < 266) this.put(x, y, at(A.img.banner, (u - 1) / 2, this.tile * 70 + v));
            }
        }
        this.XX = this.XX - this.size;
        if (this.XX <= 0) { this.size = -0.05; this.tile += 1; }
        if (this.XX >= 1) this.size = 0.05;
        if (this.tile >= 2) this.tile = 0;
        const s1 = this.myscroll.draw(), s2 = this.myscroll2.draw();
        switch (this.myscroll.current()) { case 92: this.fx = 1; break; case 93: this.fx = 2; break; case 95: this.fx = 0; break; }
        const flipStep = () => { this.flip += this.flipinc; if (this.flip <= -1) this.flipinc = 0.05; if (this.flip >= 1) this.flipinc = -0.05; };
        if (this.fx === 0) this.scrollCanvas(s1, (y) => 2 * y + 5);
        if (this.fx === 1) { const f = this.flip; this.scrollCanvas(s1, (y) => (f === 0 ? -1 : fl((2 * y + 0.5 - 215) / f + 225))); flipStep(); }
        if (this.fx === 2) {
            const f = this.flip, top = 200 + this.bounce;
            this.scrollCanvas(s2, (y) => (f === 0 ? -1 : fl((2 * y + 0.5 - top) / f + 225)));
            flipStep();
            this.bounce += this.bounceinc; if (this.bounce >= 40) this.bounceinc = -2; if (this.bounce <= 0) this.bounceinc = 2;
        }
        const p = fxRun(this.fx1, 450), q = fxRun(this.fx2, 640); // logo: sinx(50,50), siny(50,50), at (230,15) midhandled
        for (let y = 0; y < 225; y++) for (let x = 0; x < 320; x++) {
            const c3 = 2 * x + 90, r3 = 2 * y + 210;
            if (c3 >= 640 || r3 >= 450) continue;
            const i = c3 - 50;
            if (i < 0 || i >= 640) continue;
            const r2 = fl(r3 + 0.5 - (q[i] + 50));
            if (r2 < 50 || r2 >= 450) continue;
            const j = r2 - 50, c1 = fl(i + 0.5 - (p[j] + 50));
            this.put(x, y, at(A.img.logo, c1 - 235, j - 200));
        }
    }
    // a 520x450 scroll canvas (letters at y 205 + prov) at mycanvas x 60
    scrollCanvas(letters, cyOf) {
        for (let y = 0; y < 225; y++) {
            const cy = cyOf(y);
            if (cy < 0 || cy >= 450) continue;
            for (let x = 0; x < 320; x++) {
                const cx = 2 * x - 60;
                if (cx < 0 || cx >= 520) continue;
                for (const l of letters) {
                    if (cx < l.posx || cx >= l.posx + 32) continue;
                    const nb = l.ltr - 32, party = fl(nb / 10) * 27, row = fl(cy + 0.5 - (l.prov + 205));
                    if (party < 162 && row >= 0 && row < 27) this.put(x, y, at(this.A.img.syncfont, (nb % 10) * 32 + cx - l.posx, party + row));
                }
            }
        }
    }

    watch(regs) {
        for (let c = 0; c < 3; c++) {
            const v = regs[8 + c] & 31;
            if (this.oldv[c] !== v) this.hv[c] = 7; else if (this.hv[c]-- < 1) this.hv[c] = 0;
        }
    }
    remember(regs) { for (let c = 0; c < 3; c++) this.oldv[c] = regs[8 + c] & 31; }

    sync2(regs) {
        this.watch(regs);
        const img = this.hv[0] + this.hv[1] + this.hv[2] >= 7 ? this.A.img.sync2 : this.A.img.sync1;
        for (let y = 0; y < 225; y++) for (let x = 0; x < 320; x++) { // 320x96 doubled, top-left (160, 3)
            const u = 2 * x - 160, v = 2 * y - 3;
            if (u >= 0 && u < 320 && v >= 0 && v < 96) this.put(x, y, at(img, u >> 1, v >> 1));
        }
        this.remember(regs);
    }

    tcb1() {
        const cur = this.n;
        this.n = (this.n + 1) % 12;
        if (this.musicplease === 1) { this.song("tcb_music"); this.musicplease = 2; }
        const p = this.musicplease >= 1 ? fxRun(this.tcbfx, 32) : null;
        for (let py = 0; py < PH; py++) for (let px = 0; px < PW; px++) {
            const mx = 2 * (px - 8), my = 2 * (py - 10);
            let g = -1;
            if (this.musicplease === 0 && (mx < 60 || mx >= 708 || my < 60 || my >= 476)) g = 0;
            if (this.musicplease >= 1 && my >= 476) g = 0;
            if (g < 0 && p && my - 140 >= 0 && my - 140 < 32) g = at(this.A.img.tcb, fl(mx + 0.5 - (p[my - 140] + 230)), my - 140);
            if (g < 0) {
                const u = ((fl(fl((mx + 0.5) / 1.2) / 2) % 320) + 320) % 320, v = ((fl(fl((my + 0.5) / 1.2) / 2) % 240) + 240) % 240;
                g = this.noise[cur][v * 320 + u] ? this.A.NOISE : 0;
            }
            this.g[py * PW + px] = g;
        }
    }

    tcb2() {
        const A = this.A, grey = A.grey_gid[A.clr_level[this.colour]];
        if (this.colour >= 85) this.colour = 1;
        const org = new Int32Array(400 * 240); // orgcanvas.fill('#000000'): colour 0
        this.cylinder(org, 0);
        for (const l of this.t2scroll.draw()) { // otherscroller: 48x25 font, canvas 329 wide, at (0,155)
            const nb = l.ltr - 32, partx = (nb % 8) * 48, party = fl(nb / 8) * 25;
            if (party >= 200) continue;
            for (let r = 0; r < 25; r++) for (let c = Math.max(0, l.posx); c < l.posx + 48 && c < 329; c++) {
                const g = at(A.img.kh2, partx + c - l.posx, party + r);
                if (g >= 0) org[(155 + r) * 400 + c] = g;
            }
        }
        for (const ex of [9, 310]) { // scrolledge at 0.7, midhandled (13, 18)
            const ey = 165 - this.Y;
            for (let y = 0; y < 240; y++) for (let x = 0; x < 400; x++) {
                const g = at(A.img.edge, fl((x + 0.5 - ex) / 0.7 + 13), fl((y + 0.5 - ey) / 0.7 + 18));
                if (g >= 0) org[y * 400 + x] = g;
            }
        }
        this.cylinder(org, 1);
        for (let y = 111; y < 240; y++) for (let x = 318; x < 368; x++) org[y * 400 + x] = 0;
        let top;
        if (this.tcb2fx === 0) top = 254 - this.Y;
        else { this.siny += 0.05; top = 254 - Math.abs(Math.sin(this.siny) * 120); }
        for (let y = 0; y < 225; y++) for (let x = 17; x < 320; x++) { // orgcanvas x1.8 at (0,-200), at (34, top)
            const y2 = fl(2 * y + 0.5 - top);
            if (y2 < 0 || y2 >= 400) continue;
            const oy = fl((y2 + 0.5 + 200) / 1.8), ox = fl((2 * x - 34 + 0.5) / 1.8);
            if (oy < 240) this.put(x, y, org[oy * 400 + ox]);
        }
        if (this.tcb2fx === 0) { if (this.loop === 0) this.Y += this.Yinc; if (this.Y >= 30) this.Yinc = -3; if (this.Y <= -1) this.loop = 1; }
        this.bars();
        for (let y = 0; y < 75; y++) for (let x = 0; x < 320; x++) { // wizcoder 1.5x at (320,88), source-atop grey
            if (at(A.img.wizcoder, fl((2 * x + 0.5 - 320) / 1.5 + 130), fl((2 * y + 0.5 - 88) / 1.5 + 37)) >= 0) this.put(x, y, grey);
        }
        const q = fxRun(this.t2fx, 640), p = fxRun(this.t2fx2, 240), p3 = fxRun(this.t2fx3, 240);
        for (let y = 0; y < 120; y++) for (let x = 0; x < 320; x++) { // TCB: 1.5x at (320,50), siny, sinx
            const j = 2 * y, c2 = fl(2 * x + 0.5 - p[j]);
            if (c2 < 0 || c2 >= 640) continue;
            const r1 = fl(j + 0.5 - q[c2]);
            if (r1 < 0 || r1 >= 240) continue;
            this.put(x, y, at(A.img.tcblogo, fl((c2 + 0.5 - 320) / 1.5 + 48), fl((r1 + 0.5 - 50) / 1.5 + 12)));
        }
        for (let y = 0; y < 120; y++) for (let x = 0; x < 320; x++) { // ancool at (130,88), sinx
            const j = 2 * y;
            this.put(x, y, at(A.img.ancool, fl(2 * x + 0.5 - p3[j]) - 130, j - 88));
        }
        if (this.myscroll.current() === 93) this.tcb2fx = 1;
        this.colour += 1;
    }
    // scroller(ab): the 704x50 buffer, then 12 columns
    cylinder(org, ab) {
        const A = this.A, buf = new Uint8Array(704 * 25);
        for (const l of this.t2scroll2.draw()) {
            const nb = l.ltr - 32, partx = (nb % 8) * 32, party = fl(nb / 8) * 25;
            if (party >= 200) continue;
            for (let r = 0; r < 25; r++) for (let c = Math.max(0, l.posx); c < l.posx + 32 && c < 704; c++) buf[r * 704 + c] = localAt(A.img.kh, partx + c - l.posx, party + r);
        }
        if (ab === 0) this.rota -= 0.12;
        this.counter += 2;
        for (let i = 0; i < 12; i++) {
            const size = -1 * Math.sin(this.rota + i * 0.4), yrot = 30 * Math.cos(this.rota + i * 0.4);
            if (this.counter > 31) { this.counter = 0; this.rota += 0.02 * 20; }
            const party = size < 0 && ab === 0 ? 25 : size > 0 && ab === 1 ? 0 : -1;
            if (party < 0) continue;
            let x0 = -32 + 0 - i * -32 - this.counter, partx = i * 32 - this.counter, partw = 32;
            if (partx < 0) { x0 -= partx; partw += partx; partx = 0; } else partw = Math.min(partw, 704 - partx);
            const dy = yrot + 200 - 32;
            for (let y = 0; y < 240; y++) {
                const v = fl((y + 0.5 - dy) / size);
                if (v < 0 || v >= 25) continue;
                for (let x = Math.max(0, x0); x < x0 + partw && x < 400; x++) {
                    const l = buf[v * 704 + partx + x - x0];
                    if (l) org[y * 400 + x] = A.tint[party + v][l];
                }
            }
        }
    }
    bars() { // rastercanvas at (1, 0.5): ST row y shows raster row 4y+1; colour 0
        const A = this.A, PI = Math.PI;
        for (let y = 0; y < 100; y++) {
            const R = 4 * y + 1 + 0.5, c = [0, 0, 0];
            const mix = (rgb, a) => { for (let k = 0; k < 3; k++) c[k] = c[k] * (1 - a) + ((rgb >> (8 * k)) & 255) * a; };
            for (const a of this.angles) if (a > PI && a < 2 * PI) { const s = fl(R - (200 + 200 * Math.cos(a)) + 26); if (s >= 0 && s < 53) mix(A.raster_down_rows[s], 0.6); }
            for (const a of this.angles) if (a >= 0 && a <= PI / 2) { const s = fl(R - (200 + 200 * Math.cos(a)) + 16); if (s >= 0 && s < 32) mix(A.raster_up_rows[s], 1); }
            for (let i = 4; i >= 0; i--) { const a = this.angles[i]; if (a > PI / 2 && a <= PI) { const s = fl(R - (200 + 200 * Math.cos(a)) + 16); if (s >= 0 && s < 32) mix(A.raster_up_rows[s], 1); } }
            this.c0[y + OY] = (BLACK | (fl(c[2] + 0.5) << 16) | (fl(c[1] + 0.5) << 8) | fl(c[0] + 0.5)) >>> 0;
        }
        for (let i = 4; i >= 0; i--) { this.angles[i] += 0.05; if (this.angles[i] >= 2 * PI) this.angles[i] -= 2 * PI; }
    }

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

// fillpix(): 12 frames, exactly half the 320x240 pixels set, shuffled with
// the port's seeded Math.random (xorshift32 / 2^32, seed 0x2951988).
function makeNoise() {
    let s = 0x2951988;
    const rnd = () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
    const frames = [];
    for (let u = 0; u < 12; u++) {
        const t = new Uint8Array(320 * 240);
        t.fill(1, 0, 320 * 240 / 2);
        for (let i = t.length; i;) { const j = fl(rnd() * i); const x = t[--i]; t[i] = t[j]; t[j] = x; }
        frames.push(t);
    }
    return frames;
}
