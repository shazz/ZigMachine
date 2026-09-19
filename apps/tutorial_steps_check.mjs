// The stepped tutorial carts must not drift from the finished ones.
//
// docs/TUTORIAL.html puts a "Run step N" button on every step of docs/TUTORIAL.md
// and boots demo-<lang>-tutorial_steps.wasm?step=N to show it. Those carts are
// deliberate COPIES of the finished tutorial carts (apps/*/scenes/tutorial.*),
// because every snippet in TUTORIAL.md is quoted verbatim from the finished file
// and adding `if (step >= 5)` there would make the tutorial's own code untrue.
//
// A copy rots. This is the mechanism that stops it:
//
//   1. PARITY  — the stepped cart at step 7 must render frames byte-identical to
//                the finished cart. If someone edits one and not the other, the
//                fingerprints diverge and this fails.
//   2. GATING  — steps 1..6 must all render DIFFERENTLY, and step 7 must render
//                the SAME as step 6 (step 7 adds music, which never touches the
//                framebuffer). This catches the failure that actually happened
//                while writing these carts: setShadeMode was declared at module
//                scope instead of as a method on Demo, so the ABI never found it
//                and every step silently rendered the finished screen. Parity
//                alone passes in that state — it is exactly the bug it cannot see.
//
// Usage: node apps/tutorial_steps_check.mjs
import { execFileSync } from "node:child_process";

const LAST_STEP = 7;
const LANGS = [
    { name: "zig", done: "demo-tutorial.wasm", steps: "demo-tutorial_steps.wasm" },
    { name: "c", done: "demo-c-tutorial.wasm", steps: "demo-c-tutorial_steps.wasm" },
    { name: "rust", done: "demo-rust-tutorial.wasm", steps: "demo-rust-tutorial_steps.wasm" },
];
const FRAMES = 300, EVERY = 10;

// scene_hash.mjs applies --call BEFORE frame F, and its loop starts at frame 1,
// so 1 is the first moment a call can land — the same instant sealed-loader.js
// calls setShadeMode, right after skipBoot() and before any frame runs.
const CALL_FRAME = 1;

function fingerprint(cart, step) {
    const args = ["apps/scene_hash.mjs", `docs/${cart}`, String(FRAMES), String(EVERY)];
    if (step !== undefined) args.push("--call", `${CALL_FRAME}:setShadeMode:${step}`);
    const out = execFileSync("node", args, { encoding: "utf8", maxBuffer: 1 << 26 });
    return JSON.parse(out).total;
}

let failed = 0;
for (const lang of LANGS) {
    const done = fingerprint(lang.done);
    const atLast = fingerprint(lang.steps, LAST_STEP);
    if (done === atLast) {
        console.log(`${lang.name.padEnd(5)} parity  OK   step ${LAST_STEP} == ${lang.done} (${done.slice(0, 16)})`);
    } else {
        console.log(`${lang.name.padEnd(5)} parity  FAIL ${lang.steps} at step ${LAST_STEP} no longer matches ${lang.done}`);
        console.log(`        ${lang.done} ${done.slice(0, 16)} vs stepped ${atLast.slice(0, 16)}`);
        console.log("        The two carts have drifted: re-apply the change to both.");
        failed++;
    }

    // Steps 1..6 each add something visible; step 7 adds only music.
    const seen = new Map();
    const dupes = [];
    let atSix = null;
    for (let n = 1; n < LAST_STEP; n++) {
        const h = fingerprint(lang.steps, n);
        if (seen.has(h)) dupes.push(`${n} == ${seen.get(h)}`);
        else seen.set(h, n);
        if (n === LAST_STEP - 1) atSix = h;
    }
    if (dupes.length) {
        console.log(`${lang.name.padEnd(5)} gating  FAIL steps render the same screen: ${dupes.join(", ")}`);
        console.log("        Is setShadeMode still a method on Demo / an export the loader can reach?");
        failed++;
    } else if (atSix !== atLast) {
        console.log(`${lang.name.padEnd(5)} gating  FAIL step ${LAST_STEP} should look exactly like step ${LAST_STEP - 1}`);
        console.log("        Step 7 adds music only; a visual change means something else moved with it.");
        failed++;
    } else {
        console.log(`${lang.name.padEnd(5)} gating  OK   steps 1-${LAST_STEP - 1} render ${seen.size} distinct screens,`
            + ` ${LAST_STEP} adds music only`);
    }
}

if (failed) {
    console.log(`\ntutorial steps: FAILED ❌ (${failed})`);
    process.exit(1);
}
console.log("\ntutorial steps: every cart matches its finished twin and each step shows its own screen ✅");
