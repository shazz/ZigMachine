// The browser's own composite of the plane canvases, captured from headless
// Chrome: the ground truth for the RTL plane mixer's model (tools/video_mix.py).
//
//   node tools/mix_chrome.mjs <layers.rgba> <mask> <out.rgb>
//     layers.rgba  4 x 800x280 RGBA, canvas 0 first (what each canvas is given)
//     mask         which canvases are drawn (bit i = canvas i); the rest stay blank
//     out.rgb      the 800x280 composite as RGB, from a screenshot of the tube
//
// The page is docs/index.html's tube: .container (its #121010 background) holding
// the four .canvas elements, styled by the real docs/css/crt.css and given their
// pixels by putImageData, as docs/sealed-loader.js does. The CRT scanline veil
// (.container::before) is hidden: it is a cosmetic filter over the whole tube,
// not part of the machine's picture. Each raster line is shown twice (800x560);
// the capture checks the two copies agree and keeps one.
// env: PLAYWRIGHT_DIR (node_modules holding playwright), CHROME (the binary).
import { readFile, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { inflateSync } from "node:zlib";
import { fileURLToPath } from "node:url";

const W = 800, H = 280;
const CSS = fileURLToPath(new URL("../../docs/css/crt.css", import.meta.url));

async function loadPlaywright() {
    if (process.env.PLAYWRIGHT_DIR) return createRequire(process.env.PLAYWRIGHT_DIR + "/")("playwright");
    return import("playwright");
}

function pageHtml(css) {
    const canvases = [0, 1, 2, 3].map((i) => `<canvas id="${i}" width="${W}" height="${H}" class="canvas"></canvas>`);
    return `<!doctype html><style>${css}
body { margin: 0; } .container { top: 0; left: 0; margin: 0; border: 0; } .container::before { display: none; }
</style><div class="container"><div class="overlay">${canvases.join("")}</div></div>`;
}

// An 8-bit RGB or RGBA PNG (non-interlaced, as Chrome writes it) -> its pixel bytes.
function decodePng(png) {
    const ihdr = png.subarray(16, 29);
    const w = ihdr.readUInt32BE(0), h = ihdr.readUInt32BE(4), type = ihdr[9];
    if (ihdr[8] !== 8 || (type !== 2 && type !== 6) || ihdr[12] !== 0) throw new Error("expected an 8-bit RGB(A) PNG");
    const idat = [];
    for (let at = 8; at < png.length; ) {
        const len = png.readUInt32BE(at), type = png.toString("latin1", at + 4, at + 8);
        if (type === "IDAT") idat.push(png.subarray(at + 8, at + 8 + len));
        at += 12 + len;
    }
    const bpp = type === 6 ? 4 : 3;
    return { w, h, bpp, px: unfilter(inflateSync(Buffer.concat(idat)), w, h, bpp) };
}

function unfilter(raw, w, h, bpp) {
    const stride = w * bpp, out = Buffer.alloc(stride * h);
    for (let y = 0; y < h; y++) {
        const f = raw[y * (stride + 1)], src = y * (stride + 1) + 1, dst = y * stride;
        for (let i = 0; i < stride; i++) {
            const a = i >= bpp ? out[dst + i - bpp] : 0, b = y ? out[dst + i - stride] : 0;
            const c = i >= bpp && y ? out[dst + i - stride - bpp] : 0;
            const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
            const pred = [0, a, b, (a + b) >> 1, pa <= pb && pa <= pc ? a : pb <= pc ? b : c][f];
            out[dst + i] = (raw[src + i] + pred) & 255;
        }
    }
    return out;
}

// The 800x560 shot -> 800x280 RGB; each raster line must be shown twice, identically.
function rasterOf(shot) {
    const out = Buffer.alloc(W * H * 3);
    for (let y = 0; y < H; y++)
        for (let x = 0; x < W; x++) {
            const a = (2 * y * W + x) * shot.bpp, b = a + W * shot.bpp;
            for (let c = 0; c < 3; c++) {
                if (shot.px[a + c] !== shot.px[b + c]) throw new Error(`line ${y} x ${x}: the two copies differ`);
                out[(y * W + x) * 3 + c] = shot.px[a + c];
            }
        }
    return out;
}

async function main() {
    const [layersPath, maskArg, outPath] = process.argv.slice(2);
    if (!outPath) throw new Error("usage: node tools/mix_chrome.mjs <layers.rgba> <mask> <out.rgb>");
    const layers = await readFile(layersPath), mask = Number(maskArg);
    if (layers.length !== 4 * W * H * 4) throw new Error(`${layersPath}: want 4 x ${W}x${H} RGBA`);
    const { chromium } = await loadPlaywright();
    const browser = await chromium.launch({ executablePath: process.env.CHROME || "/usr/bin/google-chrome", headless: true, args: ["--disable-gpu"] });
    try {
        const page = await browser.newPage({ viewport: { width: W, height: 2 * H }, deviceScaleFactor: 1 });
        await page.setContent(pageHtml(await readFile(CSS, "utf8")));
        await page.evaluate(({ b64, mask }) => {
            const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
            for (let i = 0; i < 4; i++) {
                if (!((mask >> i) & 1)) continue;
                const ctx = document.getElementById(String(i)).getContext("2d");
                const img = ctx.createImageData(800, 280);
                img.data.set(bytes.subarray(i * 800 * 280 * 4, (i + 1) * 800 * 280 * 4));
                ctx.putImageData(img, 0, 0);
            }
        }, { b64: layers.toString("base64"), mask });
        const shot = decodePng(await page.screenshot({ clip: { x: 0, y: 0, width: W, height: 2 * H }, omitBackground: false }));
        if (shot.w !== W || shot.h !== 2 * H) throw new Error(`screenshot is ${shot.w}x${shot.h}`);
        await writeFile(outPath, rasterOf(shot));
    } finally {
        await browser.close();
    }
}

await main();
