// SYSINFO 2 checks (apps/sysinfo_check.mjs runs them): what the cart now reads of the machine,
// the speed tests' reference machines and the screen modes.
//   ident      page 1 has no n/a where the machine answers: the host (the board by ASTROLABE's
//              cycle count, the browser by its clock, else neither), the cart CPU and its measured
//              clock (board), the coprocessor, the job server, the SDK's HW version, KOS's version
//              and boot device off the ROM's system variables; page 3's sound CPU, page 2's QUEUE
//   reference  page 5's reference (Up / Down, C) switches ST -> STE -> MEGA STE ... with the results
//              kept (no test re-runs, every time the same) and each percentage recomputed: the ST's
//              and the STE's equal, the Mega STE's the ST's x 1.92 / 3.62 (refs.zig, CoreMark)
//   modes      D, L, M and F6 switch the screen (the ROM's Setscreen), both ways: the RESOLUTION
//              register and page 1 say so, the glass shows the page in the mode's geometry (desk:
//              8 x 16 cells; low: 40 columns, Tab the other half), glyph for glyph
import { readFile } from "node:fs/promises";
import { frames, page, field, glassMismatches, shownRows, mode, K } from "./sysinfo_machine.mjs";

const TAB = 0xe019, F6 = 0xe006;

async function sdkVersion() {
    const src = await readFile("machine/sdk/memmap.zig", "utf8");
    const v = parseInt(src.match(/ZM_HW_VERSION: u32 = 0x([0-9A-Fa-f_]+)/)[1].replace(/_/g, ""), 16);
    return `${v >> 16}.${(v >> 8) & 0xff}.${v & 0xff} (SDK)`;
}

/// KOS's system variables as the ROM keeps them (rom/sdk/kos.zig SysVars: u32 words).
function kosVars(s) {
    const u = new Uint32Array(s.memory.buffer, s.rom.kosSysVarsPtr(), 10);
    return { version: u[2], bootDev: u[4], ram: u[5] };
}

export async function ident(s, expect, host) {
    s.demo.key(K.F1);
    frames(s, 61); // two refreshes: the frame time needs two clock readings
    const rows = page(s), k = kosVars(s);
    const want = {
        board: ["KESTREL BOARD", "ZIGGY (RV32IM)", "ASTROLABE (MACHINE)", "IN THE CART (TESTED)"],
        browser: ["BROWSER", "WASM32 (HOST JIT)", "ASTROLABE (MACHINE)", "COPROCESSOR (TESTED)"],
        unclocked: ["NATIVE OR HARNESS", "n/a", "ASTROLABE (MACHINE)", "IN THE CART (TESTED)"],
    }[host];
    const got = ["HOST", "PROCESSOR", "CO-PROCESSOR", "BARD JOBS"].map((l) => field(rows, l));
    expect(got.join("|") === want.join("|"), `${host}: HOST / PROCESSOR / CO-PROCESSOR / BARD JOBS read ${got.join(" / ")}`);
    const mhz = field(rows, "FREQUENCY");
    expect(host === "board" ? /^(9\d|10\d)\.\d MHZ \(MEASURED\)$/.test(mhz) : mhz === "n/a", `${host}: FREQUENCY ${mhz}`);
    expect(field(rows, "HW VERSION") === (await sdkVersion()), `HW VERSION is the SDK's ZM_HW_VERSION (${field(rows, "HW VERSION")})`);
    expect(field(rows, "ROM/GEM VERSION") === `KOS ${k.version >> 16}.${k.version & 0xffff}`, `ROM/GEM VERSION is KOS's sysvars (${field(rows, "ROM/GEM VERSION")})`);
    expect(field(rows, "SYSTEM TABLE") === (host === "board" ? ">= 1.25 (IMPORTS)" : "NONE (BY NAME)"), `SYSTEM TABLE: ${field(rows, "SYSTEM TABLE")}`);
    expect(k.ram > 0 && field(rows, "MACHINE RAM") === `${Math.floor(k.ram / 1024)} Kbytes` && field(rows, "BOOT DEVICE") === "DRIVE A (COLD)",
        `MACHINE RAM and BOOT DEVICE are KOS's sysvars (${field(rows, "MACHINE RAM")}, ${field(rows, "BOOT DEVICE")})`);
    if (host !== "unclocked") {
        // FREQUENCY is measured on the board only (ASTROLABE's cycles): the browser's JIT gives no cycle count
        const na = rows.slice(3, 21).filter((r) => r.substr(18, 23).trimEnd() === "n/a").map((r) => r.substr(0, 16).trim())
            .filter((l) => !(host === "browser" && l === "FREQUENCY"));
        expect(na.length === 0, `${host}: no n/a left in page 1's SYSTEM INFO (${na.join(", ")})`);
    }
}

export async function pagesTwoThree(s, expect, host) {
    s.demo.key(K.F1 + 1);
    frames(s, 2);
    let rows = page(s);
    expect(field(rows, "QUEUE (V2)") === "PRESENT (TESTED)", "page 2: the blitter's QUEUE fills and reads back");
    expect(field(rows, "DESK MODE") === "640*480 (AVAILABLE)", "page 2: the machine answers it has the desk mode");
    s.demo.key(K.F1 + 2);
    frames(s, 2);
    rows = page(s);
    const cpu = { board: "BARD (RV32I)", browser: "AUDIOWORKLET", unclocked: "n/a" }[host];
    expect(field(rows, "SOUND CPU") === cpu && !rows.some((r) => r.includes("LEAVES IT AT 0")), `page 3: SOUND CPU ${field(rows, "SOUND CPU")}, the stale mirror note is gone`);
}

const pct = (r) => Number((r.substr(54).match(/^\s*(\d+) %/) || [])[1]);

export async function reference(s, expect, broke = false) {
    const mega = broke ? 360 : 362; // --break ref: a Mega STE score off by 0.5 % must be caught
    s.demo.key(K.F1 + 4);
    frames(s, 10);
    const st = page(s), draws = s.draws;
    s.demo.input(1); // Down: STE
    frames(s, 1);
    const ste = page(s);
    s.demo.key("c".charCodeAt(0)); // C: MEGA STE
    frames(s, 1);
    const mste = page(s);
    const tests = (rows) => rows.slice(5, 13);
    expect(st[2].includes("REFERENCE: ST = 100 %") && ste[2].includes("REFERENCE: STE") && mste[2].includes("REFERENCE: MEGA STE"), "Down then C: the reference goes ST -> STE -> MEGA STE");
    expect(tests(st).every((r, i) => r.substr(0, 54) === tests(mste)[i].substr(0, 54)) && !mste.some((r) => r.includes("RUNNING")), "the results are kept: no test re-ran, every time the same");
    const rows = tests(st).map((r, i) => [pct(r), pct(tests(ste)[i]), pct(tests(mste)[i])]).filter(([a]) => a > 0);
    expect(rows.length === 6 && rows.every(([a, b]) => a === b), `the STE's percentages are the ST's (same 68000, same bus): ${rows.map((x) => x[1]).join(" ")}`);
    expect(rows.every(([a, , c]) => Math.abs(c - (a * 192) / mega) <= 1 + a / 1000), `the Mega STE's are the ST's x 1.92 / 3.62: ${rows.map((x) => `${x[0]}->${x[2]}`).join(" ")}`);
    expect(mste[23].includes("ESTIMATED") && !st[23].includes("ESTIMATED"), "a reference other than the ST is marked estimated");
    expect(s.draws > draws, "switching the reference redraws the page");
    s.demo.input(0); s.demo.input(0); // Up twice: back to the ST
    frames(s, 1);
    expect(page(s)[2].includes("REFERENCE: ST = 100 %"), "Up walks back to the ST");
}

async function inMode(s, expect, key, want, shot) {
    s.demo.key(key);
    frames(s, 2);
    const bad = await glassMismatches(s);
    expect(mode(s) === want && bad.length === 0, `${typeof key === "number" && key > 0xe000 ? "F6" : String.fromCharCode(key)}: the screen is ${mode(s)} (want ${want}), the glass shows the page${bad.length ? " -- off at " + bad.slice(0, 5).join(" ") : ""}`);
    if (shot) await shot(s, `mode_${want}`);
}

export async function modes(s, expect, shot) {
    s.demo.key(K.F1);
    frames(s, 2);
    await inMode(s, expect, "d".charCodeAt(0), "desk", shot);
    expect(field(page(s), "RESOLUTION") === "DESK 640*480", `page 1 says DESK 640*480 (${field(page(s), "RESOLUTION")})`);
    await inMode(s, expect, "l".charCodeAt(0), "low", shot);
    let shown = shownRows(s);
    expect(shown[0].substr(37, 3) === "P1L" && shown[3].startsWith("TYPE"), "low res: the left half, the program line says P1L");
    s.demo.key(TAB);
    frames(s, 1);
    shown = shownRows(s);
    expect(shown[0].substr(37, 3) === "P1R" && shown[3].startsWith(" CART WINDOW") && (await glassMismatches(s)).length === 0, "Tab: the right half, whole on the glass");
    if (shot) await shot(s, "mode_low_right");
    await inMode(s, expect, "m".charCodeAt(0), "medium", null);
    await inMode(s, expect, F6, "desk", null);
    await inMode(s, expect, F6, "low", null);
    await inMode(s, expect, F6, "medium", null);
    expect(field(page(s), "RESOLUTION") === "MEDIUM 640*200", "F6 three times: back to medium");
}
