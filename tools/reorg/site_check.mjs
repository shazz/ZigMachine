// Does the website still load from site/? Serves site/ over HTTP and opens the pages in
// headless Chrome: every request must succeed (no 404 for a moved script, cart, disk or
// worklet), no page may throw, and the machine must reach its frame loop.
//
//   node tools/reorg/site_check.mjs [site dir] [screenshot dir]
//   env: PLAYWRIGHT_DIR  node_modules dir holding playwright (e.g. ~/.npm/_npx/<hash>/node_modules)
//        CHROME          the Chrome binary (default /usr/bin/google-chrome)
//
// Not part of the gate (it needs a browser): run it once after phase 3.
import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import { mkdirSync } from "node:fs";
import { join, resolve } from "node:path";

const SITE = resolve(process.argv[2] || "site");
const SHOTS = process.argv[3] || null;
const PORT = 3400 + Math.floor(Math.random() * 500);
const require = createRequire(process.env.PLAYWRIGHT_DIR ? join(process.env.PLAYWRIGHT_DIR, "x.js") : import.meta.url);
const { chromium } = require("playwright");

// [name, url, settle ms]: the TV (first channel), a named channel, the old bare-name links
// (?disk= / ?demo= / ?c=), the redirect, the generated pages, the retired debug page.
const PAGES = [
    ["index", "index.html", 6000],
    ["sealed", "sealed.html", 4000],
    ["channel", "index.html?channel=stniccc", 6000],
    ["channel+", "index.html?channel=stniccc", 6000, ".next_channel_button"], // a channel swap: carts/demo-<tag>.zmd
    ["disk-bare", "index.html?disk=demo-gem.zmd", 6000],
    ["demo-bare", "index.html?demo=demo-tutorial.wasm", 4000],
    ["c-image", "index.html?disk=none&c=kos-c.img", 6000],
    ["tutorial", "TUTORIAL.html", 2000, ".run"], // its Run button: an iframe on index.html?demo=demo-tutorial_steps.wasm
    ["guide", "ZIGMACHINE_GUIDE.html", 2000],
    ["debug", "debug.html", 3000],
];

async function visit(browser, [name, url, ms, click]) {
    const page = await browser.newPage();
    const bad = [];
    page.on("response", (r) => { if (r.status() >= 400) bad.push(`HTTP ${r.status()} ${r.url()}`); });
    // ERR_ABORTED: a navigation replaced before it finished (tutorial.js re-points its iframe), not a 404
    page.on("requestfailed", (r) => r.failure()?.errorText !== "net::ERR_ABORTED"
        && bad.push(`failed ${r.url()} (${r.failure()?.errorText})`));
    page.on("pageerror", (e) => bad.push(`page error: ${e.message}`));
    await page.goto(`http://127.0.0.1:${PORT}/${url}`, { waitUntil: "load" });
    const machinePage = /^(index|sealed)\.html/.test(url);
    // a real gesture, for the AudioContext (only on the machine: on the doc pages (20,20) is a link home)
    if (machinePage) await page.mouse.click(20, 20).catch(() => {});
    await page.waitForTimeout(ms);
    if (click) {
        const ok = await page.evaluate((sel) => { const e = document.querySelector(sel); if (e) e.click(); return !!e; }, click);
        if (!ok) bad.push(`no ${click} on the page`);
        await page.waitForTimeout(5000);
        for (const f of page.frames().slice(1)) { // the tutorial's embedded machine must run too
            const on = await f.evaluate("typeof demo !== 'undefined' && demo !== null").catch(() => false);
            if (!on) bad.push(`embedded machine not running: ${f.url()}`);
        }
    }
    // The click above started the sound ("Sound starts on your first click or key"): the audio chip,
    // its program and the AudioWorklet module (js/audio-worklet-sealed.js) are loaded by now.
    const audio = await page.evaluate("typeof audioNode !== 'undefined' && audioNode !== null").catch(() => false);
    // sealed-loader.js's top-level `machine` (the chip) and `demo` (the running cart)
    const running = await page.evaluate("typeof machine !== 'undefined' && machine !== null && demo !== null")
        .catch(() => false);
    if (SHOTS) await page.screenshot({ path: join(SHOTS, `${name}.png`) });
    await page.close();
    return { name, url, bad, running, audio };
}

const server = spawn("python3", ["-m", "http.server", String(PORT), "--bind", "127.0.0.1", "--directory", SITE],
    { stdio: "ignore" });
await new Promise((r) => setTimeout(r, 800));
if (SHOTS) mkdirSync(SHOTS, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.CHROME || "/usr/bin/google-chrome",
    args: ["--autoplay-policy=no-user-gesture-required"] });
let fails = 0;
try {
    for (const p of PAGES) {
        const r = await visit(browser, p);
        const machinePage = /^(index|sealed)\.html/.test(r.url);
        const ok = !r.bad.length && (!machinePage || (r.running && r.audio));
        fails += ok ? 0 : 1;
        console.log(`${ok ? "OK  " : "FAIL"} ${r.name.padEnd(10)} ${r.url}${machinePage ? `  machine ${r.running ? "running" : "NOT running"}, sound ${r.audio ? "on" : "NOT on"}` : ""}`);
        for (const b of r.bad) console.log(`       ${b}`);
    }
} finally {
    await browser.close();
    server.kill();
}
console.log(fails ? `site_check: ${fails} page(s) FAILED` : "site_check: every page loads from site/");
process.exit(fails ? 1 : 0);
