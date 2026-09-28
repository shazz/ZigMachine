// The DARK SIDE OF THE SPOON menu's ground truth: shazz's melonJS remake run in
// Chrome one setInterval tick at a time, keys pressed by timeline frame. Writes
// apps/ulm_dsots_ref.json.gz, which apps/ulm_dsots_headless.mjs compares the
// cart with. Run by hand (it needs the remake, gitignored, and Chrome):
//
//   node apps/ulm_dsots_ref.mjs [remake_dir]
//
// Per timeline frame it records MainEntity's pos/vel/animation, the viewport
// and the parallax offset; at the shot frames, the 768x540 canvas sampled at
// its even pixels (the art's 2x grid), i.e. the 384x270 the cart shows.
// codef_music.js is stubbed (the remake never plays music) and setInterval is
// captured, so nothing runs in real time.
import { readFile, writeFile } from "node:fs/promises";
import { gzipSync } from "node:zlib";
import path from "node:path";
import { TIMELINES } from "./ulm_dsots_timelines.mjs";

const PW = "/home/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs";
const ROOT = process.argv[2] || "prototypes/oldies/DarkSideOfTheSpoon-HTML5-Remake-0.9.8";
const KEYS = { left: "ArrowLeft", right: "ArrowRight", up: "ArrowUp", space: " " };
const TYPES = { ".js": "text/javascript", ".html": "text/html", ".png": "image/png", ".tmx": "text/xml" };
const { chromium } = await import(PW);

async function open(browser) {
    const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
    await page.route("http://dsots.local/**", async (route) => {
        const p = decodeURIComponent(new URL(route.request().url()).pathname);
        if (p.endsWith("codef_music.js")) return route.fulfill({ body: "function music(){this.player=null;}", contentType: "text/javascript" });
        try {
            route.fulfill({ body: await readFile(path.join(ROOT, p)), contentType: TYPES[path.extname(p)] || "application/octet-stream" });
        } catch { route.fulfill({ status: 404, body: "" }); }
    });
    await page.addInitScript(() => {
        window.__cbs = [];
        window.setInterval = (fn) => window.__cbs.push(fn);
        window.clearInterval = () => {};
    });
    // The door's me.state.change(jsApp.ScreenID.INTRO) throws (INTRO was never
    // registered): recorded, since that IS what the remake's door does.
    page.errors = [];
    page.on("pageerror", (e) => page.errors.push(e.message));
    await page.goto("http://dsots.local/index.html");
    for (let i = 0; i < 400; i++) { // the loader's ticks, until the level is up
        const up = await page.evaluate(() => { window.__cbs.at(-1)?.(); return !!window.me?.game?.getEntityByName?.("mainentity")?.length; });
        if (up) return page;
        await page.waitForTimeout(25);
    }
    throw new Error("the remake never reached its PlayScreen");
}

// One tick; the state the cart's dsotsVal() mirrors.
const tick = () => {
    window.__cbs.at(-1)();
    const e = me.game.getEntityByName("mainentity")[0];
    const plx = me.game.currentLevel.getLayerByName("parallax").parallaxLayers[0];
    const sprite = (e.current.name === "fly" ? 8 : 4) + e.current.idx;
    return [+e.pos.x, +e.pos.y, +e.vel.x, +e.vel.y, +me.game.viewport.pos.x, +me.game.viewport.pos.y, plx.baseOffset, sprite, e.lastflipX ? 1 : 0,
        jsApp.entityPos ? 1 : 0];
};

// The canvas at its even pixels, RGB.
const halved = () => {
    const c = me.video.getScreenCanvas();
    const d = c.getContext("2d").getImageData(0, 0, c.width, c.height).data;
    const out = [];
    for (let y = 0; y < c.height; y += 2) for (let x = 0; x < c.width; x += 2) { const s = (y * c.width + x) * 4; out.push(d[s], d[s + 1], d[s + 2]); }
    return out;
};

async function run(browser, tl) {
    const page = await open(browser);
    const trace = [], shots = {};
    for (let f = 0; f < tl.frames; f++) {
        for (const [k, from, to] of tl.hold) {
            if (f === from) await page.keyboard.down(KEYS[k]);
            if (f === to) await page.keyboard.up(KEYS[k]);
        }
        trace.push(await page.evaluate(tick));
        if (tl.shots.includes(f)) shots[f] = Buffer.from(await page.evaluate(halved)).toString("base64");
    }
    const errors = page.errors;
    await page.close();
    return { trace, shots, errors };
}

const browser = await chromium.launch({ executablePath: "/usr/bin/google-chrome", headless: true });
const out = {};
for (const [name, tl] of Object.entries(TIMELINES)) {
    out[name] = await run(browser, tl);
    console.log(`${name}: ${tl.frames} ticks, ${tl.shots.length} shots, last ${JSON.stringify(out[name].trace.at(-1))}, errors ${JSON.stringify(out[name].errors)}`);
}
await browser.close();
const gz = gzipSync(JSON.stringify(out), { level: 9 });
await writeFile("apps/ulm_dsots_ref.json.gz", gz);
console.log(`apps/ulm_dsots_ref.json.gz: ${gz.length} bytes`);
