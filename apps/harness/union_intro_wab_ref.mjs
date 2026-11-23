// Ground truth for the Union cracktro's WAB logo part: runs the ORIGINAL remake
// files (lib/codef_core.js, lib/codef_animatedtiles.js, eflogowabentry.js,
// eflogowab.js) unmodified in a vm, against a small software canvas 2D context,
// and returns the 350 frames the part shows (index.html:39-40, frames 600..949,
// with sequencer.js:120's "startFrame <= f < endFrame" holds at 749 and 949),
// each box-halved onto the intro's 400x280 plane (canvas/2 + (8,5)).
//
// Math.random is mulberry32(0x77ab5), the sequence apps/zig/scenes/union/wab.zig
// draws. The canvas samples bilinearly at pixel centres, composites source-over
// with globalAlpha, and ignores a globalAlpha outside [0,1], as the spec says.
import { readFile } from "node:fs/promises";
import { inflateSync } from "node:zlib";
import vm from "node:vm";

export const PLANE_W = 400, PLANE_H = 280, ORIGIN_X = 8, ORIGIN_Y = 5;
export const CANVAS_W = 768, CANVAS_H = 540;
export const ENTRY_FRAMES = 150, PART_FRAMES = 350;
const SEED = 0x77ab5;

function mulberry32(seed) {
    let a = seed >>> 0;
    return () => {
        a = (a + 0x6d2b79f5) >>> 0;
        let t = Math.imul(a ^ (a >>> 15), a | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

// 8-bit RGBA, non-interlaced: all eflogowab5.png needs.
function decodePng(buf) {
    let pos = 8, w = 0, h = 0;
    const idat = [];
    while (pos < buf.length) {
        const len = buf.readUInt32BE(pos), type = buf.toString("ascii", pos + 4, pos + 8);
        const body = buf.subarray(pos + 8, pos + 8 + len);
        if (type === "IHDR") {
            [w, h] = [body.readUInt32BE(0), body.readUInt32BE(4)];
            if (body[8] !== 8 || body[9] !== 6 || body[12] !== 0) throw new Error("PNG: need 8-bit RGBA, not interlaced");
        } else if (type === "IDAT") idat.push(body);
        pos += 12 + len;
    }
    const raw = inflateSync(Buffer.concat(idat)), out = new Uint8Array(w * h * 4), stride = w * 4;
    for (let y = 0; y < h; y++) {
        const f = raw[y * (stride + 1)], src = y * (stride + 1) + 1, row = y * stride;
        for (let x = 0; x < stride; x++) {
            const a = x >= 4 ? out[row + x - 4] : 0, b = y ? out[row - stride + x] : 0;
            const c = x >= 4 && y ? out[row - stride + x - 4] : 0;
            const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
            const pred = [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][f];
            out[row + x] = (raw[src + x] + pred) & 255;
        }
    }
    return { width: w, height: h, data: out };
}

// The subset of CanvasRenderingContext2D the four files call. Premultiplied floats.
class Context2D {
    constructor(canvas) {
        this.canvas = canvas;
        this.px = new Float32Array(canvas.width * canvas.height * 4);
        this.m = [1, 0, 0, 1, 0, 0];
        this.alpha = 1;
        this.fillStyle = "#000000";
    }
    get globalAlpha() { return this.alpha; }
    set globalAlpha(v) { if (v >= 0 && v <= 1) this.alpha = v; }
    setTransform(a, b, c, d, e, f) { this.m = [a, b, c, d, e, f]; }
    // A non-finite argument makes the call a no-op: drawTile passes w,h undefined,
    // so drawPart's scale(undefined, undefined) must change nothing.
    transform(a, b, c, d, e, f) {
        if (![a, b, c, d, e, f].every(Number.isFinite)) return;
        const [A, B, C, D, E, F] = this.m;
        this.m = [A * a + C * b, B * a + D * b, A * c + C * d, B * c + D * d, A * e + C * f + E, B * e + D * f + F];
    }
    translate(x, y) { this.transform(1, 0, 0, 1, x, y); }
    rotate(r) { this.transform(Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0, 0); }
    scale(x, y) { this.transform(x, 0, 0, y, 0, 0); }
    fillRect(x, y, w, h) {
        const [r, g, b] = [1, 3, 5].map((i) => parseInt(this.fillStyle.slice(i, i + 2), 16) / 255);
        for (let j = Math.max(0, y); j < Math.min(this.canvas.height, y + h); j++)
            for (let i = Math.max(0, x); i < Math.min(this.canvas.width, x + w); i++)
                this.blend((j * this.canvas.width + i) * 4, r, g, b, this.alpha);
    }
    getImageData(x, y, w, h) {
        const data = new Uint8ClampedArray(w * h * 4);
        for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
            const s = ((y + j) * this.canvas.width + x + i) * 4, d = (j * w + i) * 4, a = this.px[s + 3];
            for (let c = 0; c < 3; c++) data[d + c] = a ? Math.round((this.px[s + c] / a) * 255) : 0;
            data[d + 3] = Math.round(a * 255);
        }
        return { data };
    }
    blend(i, r, g, b, a) {
        const k = 1 - a, p = this.px;
        p[i] = r * a + p[i] * k; p[i + 1] = g * a + p[i + 1] * k; p[i + 2] = b * a + p[i + 2] * k; p[i + 3] = a + p[i + 3] * k;
    }
    // drawImage(img, dx, dy) or (img, sx, sy, sw, sh, dx, dy, dw, dh); CODEF passes null for dx, dy.
    drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh) {
        if (sw === undefined) return this.drawImage(img, 0, 0, img.width, img.height, sx, sy, img.width, img.height);
        dx ??= 0; dy ??= 0;
        const x0 = Math.max(sx, 0), y0 = Math.max(sy, 0), x1 = Math.min(sx + sw, img.width), y1 = Math.min(sy + sh, img.height);
        if (x1 <= x0 || y1 <= y0) return; // source clipped away: nothing drawn
        dx += ((x0 - sx) * dw) / sw; dy += ((y0 - sy) * dh) / sh;
        dw *= (x1 - x0) / sw; dh *= (y1 - y0) / sh;
        const [a, b, c, d, e, f] = this.m, det = a * d - b * c;
        const corners = [[dx, dy], [dx + dw, dy], [dx, dy + dh], [dx + dw, dy + dh]].map(([u, v]) => [a * u + c * v + e, b * u + d * v + f]);
        const minX = Math.max(0, Math.floor(Math.min(...corners.map((p) => p[0])))), maxX = Math.min(this.canvas.width, Math.ceil(Math.max(...corners.map((p) => p[0]))));
        const minY = Math.max(0, Math.floor(Math.min(...corners.map((p) => p[1])))), maxY = Math.min(this.canvas.height, Math.ceil(Math.max(...corners.map((p) => p[1]))));
        for (let py = minY; py < maxY; py++) for (let px = minX; px < maxX; px++) {
            const X = px + 0.5 - e, Y = py + 0.5 - f;
            const u = (d * X - c * Y) / det - dx, v = (-b * X + a * Y) / det - dy;
            if (u < 0 || v < 0 || u >= dw || v >= dh) continue;
            const s = this.sample(img, x0, y0, x1, y1, x0 + (u * (x1 - x0)) / dw, y0 + (v * (y1 - y0)) / dh);
            if (s[3] > 0) this.blend((py * this.canvas.width + px) * 4, s[0] / s[3], s[1] / s[3], s[2] / s[3], s[3] * this.alpha);
        }
    }
    // Bilinear over premultiplied texels, clamped to the source rectangle.
    sample(img, x0, y0, x1, y1, x, y) {
        const fx = x - 0.5, fy = y - 0.5, ix = Math.floor(fx), iy = Math.floor(fy), tx = fx - ix, ty = fy - iy;
        const out = [0, 0, 0, 0];
        for (const [ox, oy, wgt] of [[0, 0, (1 - tx) * (1 - ty)], [1, 0, tx * (1 - ty)], [0, 1, (1 - tx) * ty], [1, 1, tx * ty]]) {
            if (!wgt) continue;
            const cx = Math.min(x1 - 1, Math.max(x0, ix + ox)), cy = Math.min(y1 - 1, Math.max(y0, iy + oy));
            const i = (cy * img.width + cx) * 4, al = img.data[i + 3] / 255;
            for (let ch = 0; ch < 3; ch++) out[ch] += wgt * (img.data[i + ch] / 255) * al;
            out[3] += wgt * al;
        }
        return out;
    }
}

class CanvasElement {
    constructor() { this.width = 300; this.height = 150; this.ctx = null; }
    setAttribute(k, v) { this[k] = Number(v); }
    getContext() { return (this.ctx ??= new Context2D(this)); }
}

// Canvas (768x540, opaque) box-halved onto the plane, RGB bytes.
function toPlane(ctx, out, off) {
    for (let y = 0; y < PLANE_H; y++) for (let x = 0; x < PLANE_W; x++) {
        const cx = 2 * (x - ORIGIN_X), cy = 2 * (y - ORIGIN_Y), d = off + (y * PLANE_W + x) * 3;
        if (cx < 0 || cy < 0 || cx + 1 >= CANVAS_W || cy + 1 >= CANVAS_H) { out[d] = out[d + 1] = out[d + 2] = 0; continue; }
        for (let c = 0; c < 3; c++) {
            let sum = 0;
            for (const [i, j] of [[0, 0], [1, 0], [0, 1], [1, 1]]) sum += ctx.px[((cy + j) * CANVAS_W + cx + i) * 4 + c];
            out[d + c] = Math.round((sum / 4) * 255);
        }
    }
}

/// { frames: Uint8Array(PART_FRAMES * 400*280*3), png } from the remake in `introDir`.
export async function replayWab(introDir) {
    const png = decodePng(await readFile(`${introDir}/gfx/eflogo/eflogowab5.png`));
    const display = new CanvasElement();
    const ctx = vm.createContext({
        console: { log() {}, warn() {} },
        document: { createElement: () => new CanvasElement(), getElementById: () => ({ appendChild() {} }) },
        Image: class { constructor() { Object.assign(this, png); } },
    });
    ctx.window = ctx;
    for (const f of ["lib/codef_core.js", "lib/codef_animatedtiles.js", "eflogowabentry.js", "eflogowab.js"])
        vm.runInContext(await readFile(`${introDir}/${f}`, "utf8"), ctx, { filename: f });
    ctx.__random = mulberry32(SEED);
    vm.runInContext(`Math.random = __random;
        var __display = new canvas(${CANVAS_W}, ${CANVAS_H});
        function sequencer_getDisplayCanvas() { return __display; }
        var eflogowabentryImg = new image("gfx/eflogo/eflogowab5.png");
        var eflogowab_logoImgs = new image("gfx/eflogo/eflogowab5.png");
        var __entry = new eflogowabentry(), __fade = new eflogowab();
        __entry.init(); __fade.init();`, ctx);
    const size = PLANE_W * PLANE_H * 3, frames = new Uint8Array(PART_FRAMES * size);
    const canvas2d = vm.runInContext("__display.contex", ctx);
    for (let n = 0; n < PART_FRAMES; n++) {
        // index.html:39-40: entry renders 0..148, fade 0..198; 149 and 349 hold.
        if (n < ENTRY_FRAMES - 1) vm.runInContext(`__entry.render(${n})`, ctx);
        else if (n >= ENTRY_FRAMES && n < PART_FRAMES - 1) vm.runInContext(`__fade.render(${n - ENTRY_FRAMES})`, ctx);
        toPlane(canvas2d, frames, n * size);
    }
    return { frames, png };
}
