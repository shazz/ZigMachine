// The PHENOMENA model for apps/phenomena_headless.mjs, written from CODEF
// screen 560's screen.js (prototypes/codef/560/), not from the cart's Zig.
//
// The phase chain and the scroller arrays are screen.js's own code, nearly
// line for line (JS arrays with shift/push). Where screen.js accumulates
// doubles the model keeps the exact value as the cart must (rasterbarY in
// halves, frm in twentieths, color in thirds) AND the double, so the harness
// can say how far the remake's own rounding drifts.
//
// The picture is screen.js's drawing seen through the port's mapping: content
// line r is canvas row 2r+1, canvas column X is plane column 80+X, line 0 is
// physical row 20, and the borders are black except where a bar runs.
import { readFile } from "node:fs/promises";

export const LINE = { BAR_TOP: 64, BAR_BOTTOM: 215 };
export const CHARSET = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!'?/,.-$";
const CTRL = "^#&%";
export const PAGE1 = [[18, "   FOR HOT VHS"], [75, "  AND SOFTWARE"], [133, "SWAPPING, CONTACT"], [219, " $THE PUNISHER$"], [291, "      AT..."]];
export const PAGE2 = [[78, "    PHENOMENA"], [158, "   SKALDEV. 69"], [238, "  16142 BROMMA"], [334, "     SWEDEN!"]];
const PHASES = ["page1", "page2", "logo", "bar_top", "bar_bottom", "drop", "fade", "main"];

export class Assets {
    static async load(dir) {
        const a = new Assets();
        a.logo = await readFile(dir + "logo.raw");          // 640x64, 0 = transparent, png index + 1
        a.logoPal = await readFile(dir + "logo_pal.dat");   // 25 RGB
        const font = await readFile(dir + "font.dat");      // 45 x 26 u16
        a.font = Array.from({ length: 45 }, (_, g) => Array.from({ length: 26 }, (_, y) => font.readUInt16LE((g * 26 + y) * 2)));
        a.photon = await readFile(dir + "photon.dat");      // 15 x 70
        a.barIntro = await readFile(dir + "bar_intro.dat"); // 80 greys
        const c = await readFile(dir + "colours.dat");
        const rgb = (i) => [c[3 * i], c[3 * i + 1], c[3 * i + 2]];
        const run = (o, n) => Array.from({ length: n }, (_, i) => rgb(o + i));
        Object.assign(a, { bar: run(0, 12), red: run(12, 9), silver: run(21, 33), purple: run(54, 33),
            grey: run(87, 101), redfade: run(188, 101), hue: run(289, 360), panel: rgb(649) });
        a.msg = (await readFile(dir + "scrolltext.txt", "latin1"));
        return a;
    }
}

/// Chrome's nearest sampling with smoothing off: on an exact texel edge it
/// keeps the texel above (measured against the remake in Chrome).
export const lower = (src) => Math.ceil(src) - 1;
export const word = ([r, g, b]) => (0xFF000000 | (b << 16) | (g << 8) | r) >>> 0;
/// canvas globalAlpha: an 8-bit coverage, each channel rounded
export function blend(src, dst, a100) {
    const a = Math.floor((a100 * 255 + 50) / 100);
    return src.map((s, k) => Math.floor((s * a + dst[k] * (255 - a) + 127) / 255));
}

export class Model {
    constructor(A) {
        this.A = A;
        this.seq = { phase: 0, percent: 0, direction: 1, rasterbarY2: -80, photonY: 184, gravity: 0, bounce: -9.50, dropN: 0,
            color3: 0, t: 0, tD: 0, rectW: 640, rectShow: true, view: {} };
        this.frame = 0; this.musicFrame = null;
        this.topsD = new Float64Array(160);
        // screen.js init(): chr/frm/slc of 240, then 320 scroll+render steps.
        this.chr = Array(240).fill(" "); this.frm = Array(240).fill(0); this.frmD = Array(240).fill(0); this.slc = Array(240).fill(0);
        this.shifts = 0; this.msgIndex = 0; this.sliceCount = 0;
        this.pause = true; this.pauseTime = 250; this.scrollSpeed = 0; this.rotSpeed = 7; this.rotSpeedD = 0.35;
        for (let i = 0; i < 320; i++) { this.scrollMessage(1); this.renderNextFrames(); }
        const self = this;
        this.dna = { get len() { return self.chr.length; }, at: (i) => ({ chr: CHARSET.indexOf(self.chr[i]), frm: self.frm[i], slc: self.slc[i] }) };
    }

    // ---- the scroller (screen.js shiftLeft / addSlicesOfChar / scrollMessage / renderNextFrames)
    shiftLeft() { this.chr.shift(); this.frm.shift(); this.frmD.shift(); this.slc.shift(); this.shifts++; }
    addSlicesOfChar(c) {
        const f = this.frm[this.frm.length - 1], fD = this.frmD[this.frmD.length - 1];
        for (let i = 0; i < 8; i++) { this.chr.push(c); this.frm.push(f); this.frmD.push(fD); this.slc.push(i); }
    }
    scrollMessage(speed) {
        for (let i = 0; i < speed; i++) {
            if (this.sliceCount === 0) {
                const ch = this.A.msg.charAt(this.msgIndex);
                if (CTRL.includes(ch)) {
                    this.pause = true;
                    if (ch === "^") { this.pauseTime = 275; this.rotSpeed = -20; this.rotSpeedD = -1; }
                    else if (ch === "&") { this.pauseTime = 275; this.rotSpeed = 20; this.rotSpeedD = 1; }
                    else if (ch === "#") { this.pauseTime = 250; this.rotSpeed = -20; this.rotSpeedD = -1; }
                    else this.pauseTime = 225;
                } else {
                    this.shiftLeft(); this.addSlicesOfChar(ch);
                    this.sliceCount += 1; if (this.sliceCount > 7) this.sliceCount = 0;
                }
                this.msgIndex += 1;
                if (this.msgIndex > this.A.msg.length - 1) this.msgIndex = 90;
            } else {
                this.shiftLeft();
                this.sliceCount += 1; if (this.sliceCount > 7) this.sliceCount = 0;
            }
        }
    }
    renderNextFrames() {
        for (let i = 0; i < 240; i++) {
            this.frm[i] += this.rotSpeed;
            if (this.frm[i] > 29 * 20) this.frm[i] = 0; else if (this.frm[i] < 0) this.frm[i] += 600;
            this.frmD[i] += this.rotSpeedD;
            if (this.frmD[i] > 29) this.frmD[i] = 0; else if (this.frmD[i] < 0) this.frmD[i] += 30;
        }
    }

    // ---- the phase chain
    show(phase, level) { const s = this.seq; s.phase = phase; s.view = { phase, level, rb2: 0, photon: 0, hue: 0, rectW: 0, t: 0 }; }
    step() { this.frame++; [this.page1, this.page2, this.logo, this.barTop, this.barBottom, this.drop, this.fade, this.main][this.seq.phase].call(this); }
    page1() {
        const s = this.seq; this.show(0, 0); s.view.rb2 = s.rasterbarY2;
        s.rasterbarY2 += 3; // rasterbarY += 1.50
        if (s.rasterbarY2 >= 680) { s.rasterbarY2 = 0; s.percent = 0; this.page2(); }
    }
    page2() {
        const s = this.seq; this.show(1, s.percent);
        s.percent += s.direction;
        if (s.percent > 200) { s.direction = -1; s.percent = 100; }
        if (s.percent <= 0 && s.direction === -1) { s.percent = 0; this.logo(); }
    }
    logo() {
        const s = this.seq;
        if (s.percent <= 100) { this.show(2, s.percent); s.percent += 4; }
        else if (s.percent <= 200) { this.show(2, s.percent); s.percent += 2; }
        if (s.percent >= 200) { s.percent = 0; this.barTop(); }
    }
    barTop() {
        const s = this.seq;
        if (s.percent <= 100) { this.show(3, s.percent); s.percent += 4; }
        if (s.percent >= 100) { s.percent = 0; this.barBottom(); }
    }
    barBottom() {
        const s = this.seq;
        if (s.percent <= 100) { this.show(4, s.percent); s.percent += 4; }
        if (s.percent >= 100) { s.percent = 0; this.musicFrame = this.frame; this.drop(); }
    }
    drop() {
        const s = this.seq; this.show(5, 0); s.view.photon = Math.floor(s.photonY - 0.5) + 1;
        s.gravity += 0.30; s.photonY += s.gravity;
        if (s.photonY > 445) { s.gravity = s.bounce; s.bounce *= 0.70; }
        s.dropN++;
        if (s.bounce >= -0.70) { s.percent = 100; this.fade(); }
    }
    fade() {
        const s = this.seq; this.show(6, s.percent); s.view.photon = 445;
        s.percent -= 4;
        if (s.percent < 50) { s.percent = 0; this.main(); }
    }
    main() {
        const s = this.seq; this.show(7, 0); s.view.photon = 445;
        s.view.hue = Math.floor(s.color3 / 3);
        s.color3 += 1; if (s.color3 > 1080) s.color3 = 0;
        if (!this.pause) this.scrollMessage(this.scrollSpeed);
        else { this.pauseTime -= 1; if (this.pauseTime === 0) { this.pause = false; this.rotSpeed = 7; this.rotSpeedD = 0.35; this.scrollSpeed = 1; } }
        s.t += 1; s.tD += 0.30;
        this.renderNextFrames();
        let t2 = s.tD;
        for (let i = 0; i < 160; i++) {
            const ypos = t2 > 5 * 50 - i * 0.0033 ? 80 * Math.cos(5 * 10.50 + t2 / 6) : 80;
            this.topsD[i] = 67 + ypos;
            t2 += 1 / 6;
        }
        s.view.t = s.t; s.view.rectW = s.rectShow ? s.rectW : 0;
        if (s.rectShow) { if (s.rectW >= 0) s.rectW -= 8; else { s.rectW = 0; s.rectShow = false; } }
    }

    // ---- what the harness compares
    phaseName() { return PHASES[this.seq.view.phase]; }
    seqWords() {
        const s = this.seq, v = s.view;
        return [s.phase, s.percent, s.direction, s.rasterbarY2, s.dropN, s.color3, s.t, s.rectW, s.rectShow ? 1 : 0,
            v.phase, v.level, v.rb2, v.photon, v.hue, v.rectW, v.t];
    }
    dnaWords() {
        return [this.shifts & 255, this.chr.length, this.msgIndex, this.sliceCount, this.pause ? 1 : 0, this.pauseTime, this.scrollSpeed, this.rotSpeed];
    }
    stripTopDouble(i) { return this.topsD[i]; }
    frameAgreement() {
        let differ = 0;
        for (let i = 0; i < 240; i++) if (Math.floor(this.frmD[i]) !== Math.floor(this.frm[i] / 20)) differ++;
        return { differ, total: 240 };
    }
}
