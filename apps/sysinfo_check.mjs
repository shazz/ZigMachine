// SYSINFO (cart "sysinfo", apps/zig/scenes/sysinfo.zig): HWAM's SysInfo for the ST, on this
// machine. Boots the cart with its own disk in the drive (apps/sysinfo_machine.mjs) and holds
// every page to the machine it describes:
//   glass    each page's text is on the glass glyph for glyph (the ROM's system font)
//   values   page 1's memory lines are hwRamFree/Base/Top/Size and the ROM window as the machine
//            answers them; page 2's plane 0 is the FB_BASE register's; page 4's disk lines are
//            the .zmd's own descriptor; page 3's player and YM lines follow what the host mirrors in
//   idle     a frame between two refreshes draws nothing, and a refresh redraws only what changed
//   speed    with no host clock every test runs once and reads n/a; with one, every test has a
//            time, six a ratio to the ST, f32 a ratio to the integer multiply-add
//   menu     Space opens the GEM dialog over the page, a click on F4 shows the disk page, and the
//            page comes back whole; Q asks the host to go back to the OS (request 4)
//   node apps/sysinfo_check.mjs [<shots dir>] [--break free]
//     free: the FREE line expected 4 KB off what hwRamFree() says, so the check must fail
import { mkdir } from "node:fs/promises";
import { boot, frames, page, field, glassMismatches, glass, K } from "./sysinfo_machine.mjs";
import { grab, png } from "./skystrike_zig_frame.mjs";
import { parseDisk } from "../docs/zmdisk.js";

const BROKE = process.argv.includes("--break");
const OUT = process.argv.slice(2).find((a) => !a.startsWith("--") && a !== "free");
const errors = [];
const expect = (ok, what) => { console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) errors.push(what); };
const hex = (v) => "$" + v.toString(16).toUpperCase().padStart(6, "0");
const kb = (v) => `${String(Math.floor(v / 1024)).padStart(9)} Kbytes`;

async function shot(s, name) {
    if (!OUT) return;
    const f = grab(s), px = new Uint32Array(640 * 200);
    for (let y = 0; y < 200; y++) px.set(f.subarray((y + 40) * 800 + 80, (y + 40) * 800 + 720), y * 640);
    await png(`${OUT}/sysinfo_${name}.png`, px, 640, 200, 2);
}

async function show(s, n, name, settle = 2) {
    s.demo.key(K.F1 + n - 1);
    frames(s, settle);
    const rows = page(s);
    expect(rows[0].includes(`PAGE ${n}`), `F${n} shows page ${n} (${name})`);
    const bad = await glassMismatches(s, rows);
    expect(bad.length === 0, `page ${n}: the glass shows its text exactly${bad.length ? " -- off at " + bad.slice(0, 5).join(" ") : ""}`);
    await shot(s, `${n}_${name}`);
    return rows;
}

async function memoryPage(s) {
    const rows = await show(s, 1, "system");
    const m = s.machine;
    const free = m.hwRamFree() + (BROKE ? 4096 : 0);
    expect(field(rows, "FREE") === `${String(free).padStart(9)} Bytes`, `FREE is hwRamFree() (${field(rows, "FREE")})`);
    expect(field(rows, "CART WINDOW") === `${hex(m.hwRamBase())}-${hex(m.hwRamTop())}`, "CART WINDOW is hwRamBase()-hwRamTop()");
    expect(field(rows, "WINDOW SIZE") === kb(m.hwRamSize()), "WINDOW SIZE is hwRamSize()");
    expect(field(rows, "ROM WINDOW") === `${hex(m.hwRomRamBase())}-${hex(m.hwRomRamTop())}`, "ROM WINDOW is the ROM chip's");
    expect(field(rows, "VIDEO REGISTERS") === hex(m.hwVideoBase()), "VIDEO REGISTERS is hwVideoBase()");
    expect(field(rows, "PLANES") === "4" && field(rows, "RESOLUTION") === "MEDIUM 640*200", "4 planes, plane 0 in medium res");
    for (const l of ["HOST", "PROCESSOR", "FREQUENCY", "CO-PROCESSOR", "HW VERSION", "ROM/GEM VERSION", "SYSTEM TABLE"])
        expect(field(rows, l) === "n/a", `${l} reads n/a: no cart can read it`);
}

async function idle(s) {
    const per = [];
    for (let i = 0; i < 60; i++) { const d = s.draws; frames(s, 1); per.push(s.draws - d); }
    const busy = per.filter((d) => d > 0);
    expect(busy.length <= 2 && busy.every((d) => d <= 2), `60 idle frames: draws only at the two refreshes, the frame counter's span alone (${per.join("")})`);
    const shown = Number(field(page(s), "FRAMES SHOWN"));
    const now = new DataView(s.memory.buffer).getUint32(s.machine.hwVideoBase() + 0x30, true);
    expect(shown <= now && now - shown <= 30, `FRAMES SHOWN follows REG_FRAME (${shown} vs ${now})`);
}

async function videoSoundDisk(s) {
    let rows = await show(s, 2, "video");
    const fb0 = new DataView(s.memory.buffer).getUint32(s.machine.hwVideoBase() + 0x44, true);
    expect(field(rows, "BLITTER") === "PRESENT (TESTED)", "the blitter answers its fill test");
    expect(rows.some((r) => r.includes(`BASE ${hex(fb0)} STRIDE 640`)), "plane 0's base and stride are its registers'");
    rows = await show(s, 3, "sound");
    new Uint8Array(s.memory.buffer, s.demo.getAudioModePointer(), 1)[0] = 4;
    new Uint8Array(s.memory.buffer, s.demo.getYmRegsPointer(), 16)[7] = 0x38;
    frames(s, 31);
    rows = page(s);
    expect(field(rows, "PLAYER") === "4 SNDH (68000)" && rows.some((r) => r.includes("R07: $38")), "the player and the YM mirror follow the host, live");
    rows = await show(s, 4, "disk");
    const d = new DataView(s.disk.buffer), title = new TextDecoder().decode(s.disk.subarray(0x200, 0x240)).replace(/\0.*$/s, "");
    const date = String(d.getUint32(0x2e0, true));
    expect(field(rows, "TITLE") === title && field(rows, "DATE") === `${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6)}`, `the disk's title and date are its descriptor's (${title})`);
    const kind = parseDisk(s.disk, "demo-sysinfo.zmd").bootable ? "BOOTABLE ($1234)" : "DATA DISK"; // a data disk since it became a GEM program
    expect(field(rows, "CART SIZE") === `${d.getUint32(0x12, true)} Bytes` && field(rows, "BOOT SECTOR") === kind, `boot length and kind are the boot sector's (${kind})`);
}

async function speed(s, clocked) {
    s.demo.key(K.F1 + 4);
    frames(s, 10);
    const rows = page(s), tests = rows.slice(5, 13);
    await shot(s, clocked ? "5_speed" : "5_speed_noclock");
    if (!clocked) {
        expect(tests.every((r) => r.substr(36, 4) === "n/a ") && rows[14].includes("NO CLOCK"), "no host clock: every test once, n/a");
        return;
    }
    expect(tests.every((r) => / US /.test(r.substr(36, 18) + " ")), "a host clock: every test has a time a rep");
    expect(tests.filter((r) => / x ST\s*$/.test(r)).length === 6, "six tests against the stock ST");
    expect(/^\d+\.\d\d x INT MUL-ADD/.test(tests[2].substr(54)), "f32 against the integer multiply-add");
    for (const r of tests) console.log("     " + r.trimEnd());
}

async function menu(s) {
    s.demo.key(0x20);
    frames(s, 1);
    const px = glass(s);
    expect(px[28 * 640 + 104] === 0 && px[31 * 640 + 107] === 0, "Space opens the SysInfo Menu: its box is drawn over the page");
    await shot(s, "menu");
    const x = 104 + 56 + 20, y = 28 + 26 + 3 * 20 + 4; // F4's button (menu.zig)
    s.demo.pointer(x, y, 1);
    frames(s, 1);
    s.demo.pointer(x, y, 0);
    frames(s, 2);
    const rows = page(s);
    expect(rows[0].includes("PAGE 4"), "a click on F4 shows the disk page");
    expect((await glassMismatches(s, rows)).length === 0, "the page comes back whole when the menu closes");
    s.demo.key("q".charCodeAt(0));
    frames(s, 1);
    expect(s.demo.pollCartRequest() === 4, "Q asks the host to go back to the OS (request 4)");
}

if (OUT) await mkdir(OUT, { recursive: true });
let s = await boot("none");
frames(s, 2);
await memoryPage(s);
await idle(s);
await videoSoundDisk(s);
await speed(s, false);
await menu(s);
s = await boot("host");
frames(s, 2);
await speed(s, true);

// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BROKE) {
    const hit = errors.find((e) => e.startsWith("FREE"));
    console.log(hit ? `sysinfo_check: PASS (--break free caught: ${hit})` : "sysinfo_check: FAILED -- --break free not caught");
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `sysinfo_check: FAILED -- ${errors.join("; ")}` : "sysinfo_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
