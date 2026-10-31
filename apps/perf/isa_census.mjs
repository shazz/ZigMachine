// isa_census: which RISC-V extension / custom-instruction patterns the shelf EXECUTES, per frame
// (fpga/review/ZIGGY_ISA_EXTENSIONS.md). It runs a cart instrumented as frame_cost does, then
// matches each executed segment's wasm against peephole patterns (operand producers, flow.mjs) and
// weighs each match by the segment's count over the window. A pattern's `save` is the rv32
// instructions GCC's output loses when the extension is on (rv32imf -> +Zba/Zbb/Zbs/custom),
// read off GCC 13 -O2 code for the same C; Mc = matches x save x CPI. An ESTIMATE, like frame_cost.
//
//   node apps/perf/isa_census.mjs <cart.wasm> [--warmup 120] [--frames 30] [--json]
//   node apps/perf/isa_census.mjs --all [--json]     (every docs/demo-*.wasm with a disk, serially)
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { measure } from "./measure.mjs";
import { parseModule } from "./wasm_bin.mjs";
import { decodeFunction } from "./wasm_body.mjs";
import { producers, source } from "./flow.mjs";
import { CPI } from "./cost_model.mjs";
import { shelf } from "./run_all.mjs";

// name -> rv32 instructions saved per match (GCC 13 -O2, rv32imf vs the extension)
export const SAVE = {
    zba_shadd: 1,     // slli + add -> sh{1,2,3}add (array index, wasm2c address math)
    zbb_minmax: 2,    // branch + mv (or slt/neg/and/xor) -> min/max/minu/maxu
    zbb_clamp: 2,     // select against a constant (0, 255, ...) -> one min/max
    zbb_rot: 2,       // sll + srl + or (+ neg) -> rol/ror/rori
    zbb_bitcount: 12, // libgcc __clzsi2/__ctzsi2/__popcountsi2 call -> clz/ctz/cpop
    zbb_sext: 1,      // slli + srai -> sext.b/sext.h
    zbb_zexth: 1,     // slli + srli -> zext.h
    zbb_andn: 1,      // not + and/or/xor -> andn/orn/xnor
    zbs_bit: 1,       // li 1 + sll + and/or/xor, srli + andi, lui + and -> bset/bclr/binv/bext
    zicond: 0.5,      // branch + mv -> czero pair + or: no fewer instructions, fewer mispredicts
    fix_mulsh: 4,     // mul + mulh + srli + slli + or ((i64)a*b >> k) -> one custom MULSH
    div32: 0,         // counted only: VexRiscv DivPlugin is ~34 cycles a divide
    i64_mul: 0,       // counted only: other 64-bit multiplies
    byte_load: 0,     // counted only: texture/byte-gather candidates
    byte_store: 0,
    instr: 0,         // total wasm ops executed (context)
};

const OPS = { add: 0x6a, sub: 0x6b, mul: 0x6c, and: 0x71, or: 0x72, xor: 0x73, shl: 0x74, shr_s: 0x75, shr_u: 0x76,
    i64_mul: 0x7e, i64_shr_s: 0x87, i64_shr_u: 0x88, wrap: 0xa7, ext_s: 0xac, i32c: 0x41, i64c: 0x42, sel: 0x1b, selt: 0x1c };
const CMP = new Set([0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f]);
const singleBitHigh = (v) => { const u = v >>> 0, n = ~v >>> 0; return (u >= 2048 && (u & (u - 1)) === 0) || (n >= 2048 && (n & (n - 1)) === 0); };

function sameValue(d, a, b) {
    if (a < 0 || b < 0) return false;
    const x = d.instrs[a], y = d.instrs[b];
    return x.op === y.op && (x.op === 0x20 || x.op === OPS.i32c) && x.imm === y.imm;
}

// The patterns of instruction i: a list of SAVE keys.
function classify(d, args, i) {
    const { op, imm } = d.instrs[i], a = args[i], src = (k) => (a[k] === undefined ? -1 : source(d, args, a[k]));
    const ins = (j) => (j >= 0 ? d.instrs[j] : { op: -1, imm: null });
    const out = [];
    const shl123 = (j) => ins(j).op === OPS.shl && [1, 2, 3].includes(ins(source(d, args, args[j][1])).imm);
    if (op === OPS.add && (shl123(src(0)) || shl123(src(1)))) out.push("zba_shadd");
    // a load/store address that is a shift: wasm2c adds the memory base to it (base + (i << k))
    if ((op >= 0x28 && op <= 0x3e) && shl123(src(0))) out.push("zba_shadd");
    if (op === OPS.sel || op === OPS.selt) {
        const c = ins(src(2));
        if (CMP.has(c.op)) {
            const ca = args[src(2)].map((j) => source(d, args, j)), v = [src(0), src(1)];
            const same = (sameValue(d, v[0], ca[0]) && sameValue(d, v[1], ca[1])) || (sameValue(d, v[0], ca[1]) && sameValue(d, v[1], ca[0]));
            const konst = ins(v[0]).op === OPS.i32c || ins(v[1]).op === OPS.i32c;
            out.push(same ? (konst ? "zbb_clamp" : "zbb_minmax") : "zicond");
        } else out.push("zicond");
    }
    if (op === 0x77 || op === 0x78) out.push("zbb_rot");
    if (op >= 0x67 && op <= 0x69) out.push("zbb_bitcount");
    if (op === 0xc0 || op === 0xc1) out.push("zbb_sext");
    if (op === OPS.shr_s && ins(src(1)).op === OPS.i32c && [16, 24].includes(ins(src(1)).imm) && ins(src(0)).op === OPS.shl) out.push("zbb_sext");
    if (op === OPS.and && [0, 1].some((k) => ins(src(k)).op === OPS.i32c && ins(src(k)).imm === 0xffff)) out.push("zbb_zexth");
    if ([OPS.and, OPS.or, OPS.xor].includes(op)) {
        const notOf = (j) => ins(j).op === OPS.xor && args[j].some((q) => ins(source(d, args, q)).imm === -1);
        if (op !== OPS.xor && (notOf(src(0)) || notOf(src(1)))) out.push("zbb_andn");
        const oneShl = (j) => ins(j).op === OPS.shl && ins(source(d, args, args[j][0])).op === OPS.i32c && ins(source(d, args, args[j][0])).imm === 1;
        const k = [src(0), src(1)];
        if (k.some(oneShl) || k.some((j) => ins(j).op === OPS.i32c && singleBitHigh(ins(j).imm))) out.push("zbs_bit");
        else if (op === OPS.and && k.some((j) => ins(j).op === OPS.i32c && ins(j).imm === 1) && k.some((j) => ins(j).op === OPS.shr_u)) out.push("zbs_bit");
    }
    if ((op === OPS.i64_shr_s || op === OPS.i64_shr_u) && ins(src(1)).op === OPS.i64c && ins(src(0)).op === OPS.i64_mul) {
        const m = src(0), ext = args[m].map((j) => ins(source(d, args, j)).op);
        if (ext.every((o) => o === OPS.ext_s || o === OPS.i64c)) out.push("fix_mulsh");
    }
    if (op === OPS.i64_mul) out.push("i64_mul");
    if (op >= 0x6d && op <= 0x70 && ins(src(1)).op !== OPS.i32c) out.push("div32");
    if (op === 0x2c || op === 0x2d) out.push("byte_load");
    if (op === 0x3a) out.push("byte_store");
    return out;
}

// Per-segment pattern counts of one module, cached per function.
function segPatterns(bytes, plan) {
    const m = parseModule(bytes), perSeg = [], seen = new Map();
    for (let s = 0; s < plan.segFunc.length; s++) {
        const fi = plan.segFunc[s];
        if (!seen.has(fi)) {
            const d = decodeFunction(m, fi - m.numImportedFuncs), args = producers(m, d);
            seen.set(fi, { d, args, next: 0 });
        }
        const f = seen.get(fi), seg = f.d.segs[f.next++], c = { instr: seg.last - seg.first + 1 };
        for (let i = seg.first; i <= seg.last; i++) for (const k of classify(f.d, f.args, i)) c[k] = (c[k] ?? 0) + 1;
        perSeg.push(c);
    }
    return perSeg;
}

export async function census(cart, o = {}) {
    const disk = existsSync(cart.replace(/\.wasm$/, ".zmd")) ? cart.replace(/\.wasm$/, ".zmd") : null;
    const r = await measure(cart, { frames: o.frames ?? 30, warmup: o.warmup ?? 120, top: 5, calls: new Map(), disk, pal: true, names: {} });
    const machineDir = o.machineDir ?? "docs";
    const bytes = [await readFile(cart), await readFile(`${machineDir}/rom.wasm`)];
    const tot = {};
    r.profiles.forEach((P, mi) => {
        const pats = segPatterns(bytes[mi], P.plan), F = P.frames || 1;
        pats.forEach((c, s) => { const n = P.sum.seg[s] / F; if (n) for (const k in c) tot[k] = (tot[k] ?? 0) + n * c[k]; });
    });
    const mc = {};
    for (const k in SAVE) mc[k] = Math.round(((tot[k] ?? 0) * SAVE[k] * CPI) / 1e3) / 1e3;
    const per = Object.fromEntries(Object.keys(SAVE).map((k) => [k, Math.round(tot[k] ?? 0)]));
    return { tag: cart.replace(/^.*demo-/, "").replace(/\.wasm$/, ""), mcAvg: r.mc.avg, cartMc: r.split.cart, romMc: r.split.rom,
        icacheMc: r.split.icache, codeKB: r.codeKB, perFrame: per, savedMc: mc };
}

async function main() {
    const argv = process.argv.slice(2), o = { json: argv.includes("--json") };
    const val = (f) => { const i = argv.indexOf(f); return i >= 0 ? Number(argv[i + 1]) : undefined; };
    o.warmup = val("--warmup"); o.frames = val("--frames");
    const carts = argv.includes("--all") ? shelf("docs") : argv.filter((a) => a.endsWith(".wasm"));
    for (const c of carts) {
        let row;
        try { row = await census(c, o); } catch (e) { row = { tag: c, error: String(e.message).slice(0, 160) }; }
        console.log(o.json ? JSON.stringify(row) : `${row.tag}: ${JSON.stringify(row.savedMc ?? row.error)}`);
    }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
    main().catch((e) => { console.error(e.stack ?? e.message); process.exit(2); });
}
