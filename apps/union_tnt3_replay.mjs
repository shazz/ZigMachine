// The Union Demo remake's TNT3 screen, run for real in node: its own
// screens/tnt3/screen.js on lib/codef_core.js, lib/codef_3d_v2.js (three.js r49)
// and lib/codef_scrolltext_updown.js, over a mock 2D canvas.
//
// The mock implements exactly what those files call, with the port's documented
// halving rule and nothing else (union_tnt3.zig, effects/canvas_poly.zig):
//   - paths fill by the nonzero rule, a pixel being inside when its centre is:
//     along the row, an edge (p0, p1) with y in [p0.y, p1.y) or [p1.y, p0.y)
//     crosses at p0.x + (sy - p0.y) * (p1.x - p0.x) / (p1.y - p0.y), no antialias;
//   - drawImage copies whole pixels (these screens only translate by integers),
//     transparent pixels leaving the destination alone;
//   - a non-string fillStyle is ignored, and assigning a canvas's width or height
//     clears it and resets its state, as the canvas spec says;
//   - the screen shown at ST (X, Y) is canvas pixel (2X, 2Y).
// Drawing is recorded and evaluated only where a pixel is asked for, so a replay
// of thousands of frames stays cheap.
import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { inflateSync } from "node:zlib";
import vm from "node:vm";

const REMAKE = "prototypes/oldies/Union-Demo-HTML5-Remake-0.9.8";
const CLEAR = -1;
// --break: a replay that is wrong on purpose, so the check must FAIL.
//   overdraw: three.js's Nb() does nothing (a codef3d.zig detail);
//   ball: the sphere's radius is 79, not 80 (a union_tnt3/models.zig detail).
const BREAKS = {
    overdraw: ["lib/codef_3d_v2.js", "function Nb(a,b){", "function Nb(a,b){return;"],
    ball: ["screens/tnt3/screen.js", "this.CreateUnitSphere(22.5, 22.5, 80)", "this.CreateUnitSphere(22.5, 22.5, 79)"],
};
export const BREAK_NAMES = Object.keys(BREAKS);

/// The remake's directory, or null. prototypes/ is not in git: it is looked for
/// here, then in the main checkout (a worktree has none of its own).
export function findRemake(dir) {
    if (dir) return existsSync(`${dir}/screens/tnt3/screen.js`) ? dir : null;
    const roots = ["."];
    try {
        const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { stdio: ["ignore", "pipe", "ignore"] });
        roots.push(dirname(common.toString().trim()));
    } catch {
        // not a git checkout: only "." is looked at
    }
    return roots.map((r) => join(r, REMAKE)).find((d) => existsSync(`${d}/screens/tnt3/screen.js`)) ?? null;
}

function decodePng(path) {
    const buf = readFileSync(path);
    let pos = 8, w = 0, h = 0, depth = 0, type = 0, palette = null;
    const idat = [];
    while (pos < buf.length) {
        const len = buf.readUInt32BE(pos), kind = buf.toString("latin1", pos + 4, pos + 8), data = buf.subarray(pos + 8, pos + 8 + len);
        if (kind === "IHDR") [w, h, depth, type] = [data.readUInt32BE(0), data.readUInt32BE(4), data[8], data[9]];
        if (kind === "PLTE") palette = data;
        if (kind === "tRNS" || (kind === "IHDR" && data[12])) throw new Error(`${path}: tRNS/interlace not handled`);
        if (kind === "IDAT") idat.push(data);
        pos += 12 + len;
    }
    if (type !== 3) throw new Error(`${path}: not a palette PNG`);
    const raw = inflateSync(Buffer.concat(idat)), stride = Math.ceil((w * depth) / 8);
    const rows = new Uint8Array(h * stride);
    for (let y = 0; y < h; y++) {
        const f = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
        for (let x = 0; x < stride; x++) {
            const a = x ? rows[y * stride + x - 1] : 0, b = y ? rows[(y - 1) * stride + x] : 0, c = x && y ? rows[(y - 1) * stride + x - 1] : 0;
            const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
            const pred = [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][f];
            rows[y * stride + x] = (src[x] + pred) & 255;
        }
    }
    const px = new Int32Array(w * h);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const bit = x * depth, i = (rows[y * stride + (bit >> 3)] >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
        px[y * w + x] = (palette[3 * i] << 16) | (palette[3 * i + 1] << 8) | palette[3 * i + 2];
    }
    return { width: w, height: h, sample: (x, y) => px[y * w + x] };
}

function parseColor(s, old) {
    if (typeof s !== "string") return old;
    let m = /^#([0-9a-f]{6})$/i.exec(s);
    if (m) return parseInt(m[1], 16);
    m = /^rgba?\((\d+),(\d+),(\d+)(,1)?\)$/.exec(s.replace(/\s/g, ""));
    if (m) return (+m[1] << 16) | (+m[2] << 8) | +m[3];
    throw new Error(`fillStyle ${s} not handled`);
}

function inside(subpaths, sx, sy) {
    let winding = 0;
    for (const pts of subpaths) for (let i = 0; i < pts.length; i++) {
        const [x0, y0] = pts[i], [x1, y1] = pts[(i + 1) % pts.length];
        const down = y0 <= sy && sy < y1;
        if (!down && !(y1 <= sy && sy < y0)) continue;
        if (x0 + ((sy - y0) * (x1 - x0)) / (y1 - y0) <= sx) winding += down ? 1 : -1;
    }
    return winding !== 0;
}

/// A recorded canvas: ops since the last clear that covers them.
class Ctx {
    constructor(el) { this.el = el; this.reset(); }
    reset() {
        this.ops = [];
        this.m = [1, 0, 0, 1, 0, 0];
        this.fillStyle_ = 0;
        this.globalAlpha = 1;
        this.globalCompositeOperation = "source-over";
        this.path = [];
    }
    set fillStyle(v) { this.fillStyle_ = parseColor(v, this.fillStyle_); }
    get fillStyle() { return this.fillStyle_; }
    setTransform(a, b, c, d, e, f) { this.m = [a, b, c, d, e, f]; }
    translate(x, y) { if (Number.isFinite(x) && Number.isFinite(y)) { const [a, b, c, d, e, f] = this.m; this.m = [a, b, c, d, e + a * x + c * y, f + b * x + d * y]; } }
    scale(x, y) { if (Number.isFinite(x) && Number.isFinite(y)) { const [a, b, c, d, e, f] = this.m; this.m = [a * x, b * x, c * y, d * y, e, f]; } }
    rotate(r) { if (Number.isFinite(r) && r !== 0) throw new Error("rotate not handled"); }
    offset() {
        const [a, b, c, d, e, f] = this.m;
        if (a !== 1 || b !== 0 || c !== 0 || d !== 1 || !Number.isInteger(e) || !Number.isInteger(f)) throw new Error(`transform ${this.m} not handled for images`);
        return [e, f];
    }
    push(op) {
        if (this.globalAlpha !== 1 || this.globalCompositeOperation !== "source-over") throw new Error("alpha/composite not handled");
        if (op.opaque) this.ops = this.ops.filter((o) => !(o.x0 >= op.x0 && o.y0 >= op.y0 && o.x1 <= op.x1 && o.y1 <= op.y1));
        this.ops.push(op);
    }
    rect(x, y, w, h, color) {
        const [e, f] = this.offset();
        this.push({ x0: e + x, y0: f + y, x1: e + x + w, y1: f + y + h, opaque: true, at: () => color });
    }
    fillRect(x, y, w, h) { this.rect(x, y, w, h, this.fillStyle_); }
    clearRect(x, y, w, h) { this.rect(x, y, w, h, CLEAR); }
    beginPath() { this.path = []; }
    moveTo(x, y) { this.path.push([this.device(x, y)]); }
    lineTo(x, y) { this.path.at(-1).push(this.device(x, y)); }
    closePath() {}
    device(x, y) { const [a, b, c, d, e, f] = this.m; return [a * x + c * y + e, b * x + d * y + f]; }
    fill() {
        const sub = this.path.map((p) => p.slice()), color = this.fillStyle_, all = sub.flat();
        const xs = all.map((p) => p[0]), ys = all.map((p) => p[1]);
        this.push({ x0: Math.floor(Math.min(...xs)), y0: Math.floor(Math.min(...ys)), x1: Math.ceil(Math.max(...xs)) + 1, y1: Math.ceil(Math.max(...ys)) + 1,
            at: (x, y) => (inside(sub, x + 0.5, y + 0.5) ? color : CLEAR) });
    }
    drawImage(src, ...a) {
        const [sx, sy, sw, sh, dx, dy] = a.length === 2 ? [0, 0, src.width, src.height, a[0], a[1]] : [a[0], a[1], a[2], a[3], a[4] ?? 0, a[5] ?? 0];
        const [e, f] = this.offset(), x0 = e + dx, y0 = f + dy;
        const sample = src.sample ?? src.ctx.freeze();
        this.push({ x0, y0, x1: x0 + sw, y1: y0 + sh, at: (x, y) => sample(sx + x - x0, sy + y - y0) });
    }
    freeze() {
        const ops = this.ops.slice();
        return (x, y) => {
            for (let i = ops.length - 1; i >= 0; i--) {
                const o = ops[i];
                if (x < o.x0 || y < o.y0 || x >= o.x1 || y >= o.y1) continue;
                const v = o.at(x, y);
                if (v !== CLEAR || o.opaque) return v;
            }
            return CLEAR;
        };
    }
    getImageData() { return { data: new Uint8ClampedArray(16) }; }
    putImageData() {}
    stroke() { throw new Error("stroke not handled"); }
}

class CanvasEl {
    constructor(w = 300, h = 150) { this.w = w; this.h = h; this.ctx = new Ctx(this); }
    get width() { return this.w; }
    set width(v) { this.w = +v; this.ctx.reset(); }
    get height() { return this.h; }
    set height(v) { this.h = +v; this.ctx.reset(); }
    setAttribute(k, v) { this[k] = v; }
    getContext() { return this.ctx; }
}

/// The screen object, reset as melonJS does on entry. frame(keys) runs one
/// update() + draw() with the named melonJS key actions held; shot() gives the
/// ST screen as 0xRRGGBB (CLEAR where nothing was drawn). `brk` names a BREAKS entry.
export function makeRemake(REMAKE, brk = null) {
    if (brk !== null && !(brk in BREAKS)) throw new Error(`--break takes ${BREAK_NAMES.join("|")}, not ${brk}`);
    const system = new CanvasEl(640, 400);
    class HTMLImageElement {}
    const images = {};
    for (const n of ["stars", "fonts"]) images[`img_tnt3_${n}`] = Object.assign(new HTMLImageElement(), decodePng(`${REMAKE}/screens/tnt3/${n}.png`));
    const state = { song: null, left: false, held: new Set() };
    const sandbox = {
        console: { log() {}, warn() {}, debug() {} }, Math, Float32Array, Int32Array, Uint8ClampedArray, Array, Date, HTMLImageElement,
        document: { createElement: () => new CanvasEl() }, window: {},
        me: {
            ScreenObject: { extend: (proto) => { function S() { this.init(); } Object.assign(S.prototype, proto, { parent() {} }); return S; } },
            video: { getSystemCanvas: () => system },
            loader: { getImage: (n) => images[n] },
            input: { isKeyPressed: (k) => state.held.has(k) },
            state: { change: () => { state.left = true; } },
            sys: {},
        },
        jsApp: { YMPlayer: { stop() {}, play() {}, fetchFile: (f) => { state.song = f; } }, ScreenID: { MENU_LOADER: 0 } },
    };
    sandbox.self = sandbox;
    vm.createContext(sandbox);
    for (const f of ["lib/codef_core.js", "lib/codef_3d_v2.js", "lib/codef_scrolltext_updown.js", "screens/tnt3/screen.js"]) {
        let src = readFileSync(`${REMAKE}/${f}`, "utf8");
        if (brk !== null && BREAKS[brk][0] === f) {
            const [, from, to] = BREAKS[brk];
            if (src.split(from).length !== 2) throw new Error(`--break ${brk}: "${from}" is not in ${f} exactly once`);
            src = src.replace(from, to);
        }
        vm.runInContext(src, sandbox, { filename: f });
    }
    const screen = vm.runInContext("new tnt3Screen()", sandbox);
    screen.onResetEvent();
    return {
        state,
        frame(keys = []) {
            state.held = new Set(keys);
            screen.update();
            screen.draw();
        },
        shot() {
            const sample = system.ctx.freeze(), out = new Int32Array(320 * 200);
            for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) out[y * 320 + x] = sample(2 * x, 2 * y);
            return out;
        },
    };
}
