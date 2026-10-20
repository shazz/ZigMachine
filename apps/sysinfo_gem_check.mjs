// SYSINFO as a GEM program (apps/zig/scenes/sysinfo.zig on a DATA disk, as ST Replay is):
// its disk boots GEM, GEM's FLOPPY window lists BOOT.WSM, a double-click runs it (request 3)
// and Q goes back to the desktop (request 4), over and over. GEM is apps/gem_headless.mjs's,
// which services the swap protocol the way docs/sealed-loader.js does.
//   disk     docs/demo-sysinfo.zmd is a data disk (boot sector sums to $0000) whose only
//            program is BOOT.WSM, and BOOT.WSM depacks (romDepack, as the loader does) to
//            docs/demo-sysinfo.wasm byte for byte: what tools/glass_shelf.py matches the board
//            image by
//   launch   double-clicking BOOT.WSM in the floppy window runs SysInfo: page 1 is on the glass
//   quit     Q brings GEM back: the desktop's own screen, not SysInfo's
//   reuse    LAUNCHES round trips, more than the ROM's MAX_GUI: SysInfo opens a Gui and a Dialog
//            every launch, so a leaked handle would leave the last launch without its menu
//   page 4   SysInfo reads the disk it was launched from: DATA DISK, BOOT.WSM in its FAT
//   node apps/sysinfo_gem_check.mjs [--break bootable]
//     bootable: hold the disk to the bootable kind it used to be, so the check must fail
import { readFile } from "node:fs/promises";
import { bootGem } from "./gem_headless.mjs";
import { parseDisk } from "../docs/zmdisk.js";
import { page } from "./sysinfo_machine.mjs";

const BREAK = process.argv.includes("--break");
const FLOPPY = [70, 40], FIRST_FILE = [75, 66]; // gem_headless.mjs's measured cells
const LAUNCHES = 3; // > MAX_GUI (2) in rom/rom_main.zig
const BLOCK = 512;
const errors = [];
const expect = (ok, what) => { console.log(`  ${ok ? "ok  " : "FAIL"} ${what}`); if (!ok) errors.push(what); };

const zmd = new Uint8Array(await readFile("docs/demo-sysinfo.zmd"));
const cart = new Uint8Array(await readFile("docs/demo-sysinfo.wasm"));
const disk = parseDisk(zmd, "demo-sysinfo.zmd");

/// BOOT.WSM as the loader runs it: the packed image depacked by the ROM into the cart window
/// (sealed-loader.js unpackCart), on a throwaway machine so the GEM under test is untouched.
async function depacked(entry) {
    const { machine, rom, memory } = await bootGem();
    const u8 = zmd.subarray(entry.start, entry.start + entry.len);
    const src = machine.hwRomRamBase() + machine.hwRomRamUsed();
    new Uint8Array(memory.buffer, src, u8.length).set(u8);
    const n = rom.romDepack(src, u8.length, machine.hwRamBase(), machine.hwRamSize());
    if (!n) throw new Error("BOOT.WSM does not depack (romDepack returned 0)");
    return new Uint8Array(memory.buffer.slice(machine.hwRamBase(), machine.hwRamBase() + n));
}

async function checkDisk() {
    expect(disk.bootable === BREAK, `the disk is a data disk: GEM boots for it (${disk.bootable ? "$1234" : "$0000"})`);
    const names = Object.keys(disk.mounted.files);
    const prog = disk.mounted.files["BOOT.WSM"];
    expect(names.length === 1 && prog && prog.type === 0, `its FAT holds one program, BOOT.WSM (${names.join(" ")})`);
    if (!prog) return null;
    const bytes = await depacked(prog);
    expect(bytes.length === cart.length && bytes.every((b, i) => b === cart[i]), "BOOT.WSM is demo-sysinfo.wasm, byte for byte");
    return bytes;
}

/// GEM over the disk, as the loader brings it up: the drive serves the real image's blocks,
/// and the FLOPPY window gets the real FAT.
async function gemOverDisk(program) {
    const gem = await bootGem();
    gem.demoImports.env.diskReadBlock = (block, dst) => {
        const src = zmd.subarray(block * BLOCK, block * BLOCK + BLOCK);
        new Uint8Array(gem.memory.buffer, dst, src.length).set(src);
        return src.length;
    };
    gem.programs["BOOT.WSM"] = program;
    const back = gem.backToOs.bind(gem);
    gem.backs = 0; // request 4s the harness serviced: GEM brought back
    gem.backToOs = () => { gem.backs++; back(); };
    gem.mount(Object.entries(disk.mounted.files).map(([name, f]) => ({ name, type: f.type, size: f.len, date: 0 })));
    return gem;
}

const settle = (gem, n) => { for (let i = 0; i < n; i++) gem.frame(); };
const rows = (gem) => page({ memory: gem.memory });

function launch(gem) {
    gem.open(...FLOPPY);
    settle(gem, 6);
    gem.open(...FIRST_FILE);
    settle(gem, 6);
}

async function roundTrips(gem) {
    const desk = gem.hash();
    for (let i = 1; i <= LAUNCHES; i++) {
        const before = gem.swaps;
        launch(gem);
        expect(gem.swaps === before + 1, `launch ${i}: the double-click on BOOT.WSM ran it (request 3)`);
        expect(rows(gem)[0].includes("PAGE 1"), `launch ${i}: SysInfo shows page 1`);
        if (i === LAUNCHES) return desk;
        gem.key(0x71); // q: quit
        settle(gem, 8);
        expect(gem.backs === i, `quit ${i}: Q brought GEM back (request 4)`);
    }
    return desk;
}

async function lastLaunch(gem, desk) {
    const pageHash = gem.hash();
    gem.key(0x20); // Space: the SysInfo Menu, a ROM dialog over the page
    settle(gem, 2);
    expect(gem.hash() !== pageHash, `after ${LAUNCHES} launches Space still opens the menu: the ROM's handles were reclaimed`);
    gem.key(0xe004); // F4 on the menu: the disk page
    settle(gem, 2);
    const r = rows(gem);
    const field = (label) => (r.find((x) => x.includes(label)) || "").split(":").slice(1).join(":").trim();
    expect(r[0].includes("PAGE 4") && field("BOOT SECTOR").startsWith("DATA DISK"), `page 4 reads the disk it was launched from: ${field("BOOT SECTOR")}`);
    expect(r.some((x) => x.includes("BOOT.WSM")), "page 4 lists BOOT.WSM in its FAT");
    gem.key(0x71);
    settle(gem, 8);
    expect(gem.backs === LAUNCHES && gem.hash() === desk, "the last Q leaves GEM's desktop exactly as it was");
}

const program = await checkDisk();
if (program) {
    const gem = await gemOverDisk(program);
    const desk = await roundTrips(gem);
    expect(gem.swaps === LAUNCHES, `${LAUNCHES} programs run off the disk (${gem.swaps})`);
    await lastLaunch(gem, desk);
}

// exitCode, never process.exit() (see apps/mod_sfx_check.mjs: node 24 deadlocks at exit).
if (BREAK) {
    const hit = errors.find((e) => e.startsWith("the disk is a data disk"));
    console.log(hit ? `sysinfo_gem_check: PASS (--break bootable caught: ${hit})` : "sysinfo_gem_check: FAILED -- --break bootable not caught");
    process.exitCode = hit ? 0 : 1;
} else {
    console.log(errors.length ? `sysinfo_gem_check: FAILED -- ${errors.join("; ")}` : "sysinfo_gem_check: all pass");
    process.exitCode = errors.length ? 1 : 0;
}
