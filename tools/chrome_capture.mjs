// Chrome reference frames of a Union Demo remake screen: runs the remake's own
// screen.js (and its CODEF libs) in headless Chrome with melonJS stubbed down to
// what the screen touches, steps update()+draw() and dumps the system canvas.
// These frames are the ground truth for the ports' Chrome-exact replays
// (libs/zig/effects/chrome_draw.zig); keep them out of git, regenerate them.
//
//   node tools/chrome_capture.mjs <screen> <frame,frame,...> <outdir>
//     screen   L16 | superscroller (SCREENS below)
//     writes   <outdir>/f<frame>.rgba (the whole canvas, RGBA), meta.json and
//              scrolltext.txt (jsApp.scrolltext as read from main.js)
//   env: PLAYWRIGHT_DIR  node_modules dir holding playwright, when it is not
//                        resolvable from here (e.g. ~/.npm/_npx/<hash>/node_modules)
//        CHROME          the Chrome binary (default /usr/bin/google-chrome)
//        REMAKE          the remake's directory (default prototypes/oldies/Union-Demo-HTML5-Remake-0.9.8)
//
// Frame numbers follow each port's headless harness: superscroller frame N is
// the canvas after N update()+draw() calls, L16 frame N after N+1 (its harness
// counts the first draw as frame 0). Chrome runs with --disable-gpu: the
// software (Skia raster) canvas is the path the models reproduce.
// One browser at a time: the box is short on memory.
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { createRequire } from "node:module";

// prototypes/ is not in git: point REMAKE at a checkout that has it when running from a worktree
const REMAKE = (process.env.REMAKE || new URL("../prototypes/oldies/Union-Demo-HTML5-Remake-0.9.8", import.meta.url).pathname).replace(/\/?$/, "/");

const SCREENS = {
    superscroller: {
        ctor: "superScrollerScreen", w: 640, h: 400, calls: (n) => n,
        libs: ["lib/codef_core.js", "lib/codef_scrolltext.js", "screens/superscroller/screen.js"],
        images: { img_tcb2_fonts: "fonts2.png", img_tcb2_overlay: "overlay.png", img_tcb2_rasters: "rasters.png" },
    },
    L16: {
        ctor: "l16Screen", w: 832, h: 572, calls: (n) => n + 1,
        libs: ["lib/codef_core.js", "lib/codef_scrolltext.js", "screens/L16/screen.js"],
        images: {
            img_l16_fonts: "font.png", img_l16_background: "screenback.png", img_l16_raster: "raster.png",
            img_l16_waterraster: "watergrad2.png", img_l16_unionSprite: "union_bob.png",
        },
    },
};

/// jsApp.scrolltext in main.js: double-quoted literals joined by '+', read without eval.
async function mainScrolltext() {
    const src = await readFile(REMAKE + "main.js", "latin1");
    const start = src.indexOf("scrolltext :");
    if (start < 0) throw new Error("main.js: no jsApp.scrolltext");
    let text = "";
    const lit = /\s*"((?:[^"\\]|\\["\\'])*)"\s*(\+?)/y;
    lit.lastIndex = start + "scrolltext :".length;
    for (let m; (m = lit.exec(src)); ) {
        text += m[1].replace(/\\(["\\'])/g, "$1");
        if (!m[2]) return text;
    }
    throw new Error("main.js: jsApp.scrolltext is not a plain chain of string literals");
}

async function loadPlaywright() {
    if (process.env.PLAYWRIGHT_DIR) return createRequire(process.env.PLAYWRIGHT_DIR + "/")("playwright");
    return import("playwright");
}

function pageHtml(cfg, text) {
    const scripts = cfg.libs.map((s) => `<script src="/${s}"></script>`).join("");
    return `<!doctype html><canvas id=c width=${cfg.w} height=${cfg.h}></canvas><script>
var me = { ScreenObject: { extend(o) { var C = function () { this.init.apply(this, arguments); }; C.prototype = Object.assign({ parent() {} }, o); return C; } },
  loader: { getImage(n) { return window.IMGS[n]; } }, video: { getSystemCanvas() { return document.getElementById('c'); } },
  input: { isKeyPressed() { return false; } }, audio: { playTrack() {}, stopTrack() {} }, state: { change() {} }, sys: {} };
var jsApp = { YMPlayer: { stop() {}, play() {}, fetchFile() {} }, mainscrollerPos: 0, ScreenID: {}, scrolltext: ${JSON.stringify(text)} };
</script>${scripts}`;
}

async function main() {
    const [name, list, out] = process.argv.slice(2);
    const cfg = SCREENS[name];
    if (!cfg || !list || !out) throw new Error("usage: node tools/chrome_capture.mjs <L16|superscroller> <frame,frame,...> <outdir>");
    const frames = list.split(",").map(Number).sort((a, b) => a - b);
    if (frames.some((f) => !Number.isInteger(f) || f < 0)) throw new Error(`frames must be whole numbers >= 0: ${list}`);
    await mkdir(out, { recursive: true });
    const text = await mainScrolltext();
    await writeFile(`${out}/scrolltext.txt`, text, "latin1"); // what jsApp.scrolltext was
    const html = pageHtml(cfg, text);
    const dir = `screens/${name}/`;
    const { chromium } = await loadPlaywright();
    const browser = await chromium.launch({ executablePath: process.env.CHROME || "/usr/bin/google-chrome", headless: true, args: ["--disable-gpu"] });
    try {
        const page = await browser.newPage();
        const pageErrors = [];
        page.on("pageerror", (e) => pageErrors.push(e.message));
        await page.route("http://remake.local/**", async (route) => {
            const p = new URL(route.request().url()).pathname.slice(1);
            if (p === "") return route.fulfill({ body: html, contentType: "text/html" });
            if (p.includes("..")) return route.fulfill({ status: 404, body: "" });
            try {
                await route.fulfill({ body: await readFile(REMAKE + p), contentType: p.endsWith(".png") ? "image/png" : "text/javascript" });
            } catch { await route.fulfill({ status: 404, body: "" }); }
        });
        await page.goto("http://remake.local/");
        await page.evaluate(async ({ images, dir, ctor }) => {
            const load = (src) => new Promise((ok, fail) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => fail(new Error(src)); i.src = src; });
            window.IMGS = {};
            for (const [k, f] of Object.entries(images)) window.IMGS[k] = await load(dir + f);
            window.S = new window[ctor]();
            for (const v of Object.values(window.S)) if (v && v.img instanceof HTMLImageElement) await v.img.decode(); // images built from paths
            window.S.onResetEvent();
            window.CALLS = 0;
        }, { images: cfg.images, dir, ctor: cfg.ctor });
        const check = () => { if (pageErrors.length) throw new Error(`screen.js threw: ${pageErrors.join("; ")}`); };
        check();
        for (const f of frames) {
            const b64 = await page.evaluate((calls) => {
                while (window.CALLS < calls) { window.S.update(); window.S.draw(); window.CALLS++; }
                const c = document.getElementById("c");
                const d = c.getContext("2d").getImageData(0, 0, c.width, c.height).data;
                let bin = "";
                for (let i = 0; i < d.length; i += 0x8000) bin += String.fromCharCode.apply(null, d.subarray(i, i + 0x8000));
                return btoa(bin);
            }, cfg.calls(f));
            check();
            await writeFile(`${out}/f${f}.rgba`, Buffer.from(b64, "base64"));
        }
        await writeFile(`${out}/meta.json`, JSON.stringify({ screen: name, w: cfg.w, h: cfg.h, frames }, null, 1));
        console.log(`${name}: ${frames.length} frames (${cfg.w}x${cfg.h} RGBA) -> ${out}`);
    } finally {
        await browser.close();
    }
}

await main();
