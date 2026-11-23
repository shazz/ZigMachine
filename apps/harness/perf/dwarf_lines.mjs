// file:line for a wasm code offset, from the DWARF .debug_line of a named twin
// (tools/perf_names.sh builds with the debug info kept). Release carts inline almost
// everything into demo_main.frame, so a function name alone often says nothing; the
// line table still says which source line a loop's first instruction came from.
// DWARF 4 and 5 line programs; wasm addresses are offsets into the code section payload.
import { Reader } from "./wasm_bin.mjs";

const FORM = { string: 0x08, line_strp: 0x1f, strp: 0x0e, udata: 0x0f, data1: 0x0b, data2: 0x05, data4: 0x06, data8: 0x07, data16: 0x1e, block: 0x09 };
const u16 = (r) => r.u8() | (r.u8() << 8);
const u32 = (r) => (r.u8() | (r.u8() << 8) | (r.u8() << 16) | (r.u8() << 24)) >>> 0;
const cstr = (buf, at) => { let e = at; while (buf[e]) e++; return new TextDecoder().decode(buf.subarray(at, e)); };

function readForm(r, form, strs) {
    if (form === FORM.string) { const s = cstr(r.buf, r.pos); r.pos += Buffer.byteLength(s) + 1; return s; }
    if (form === FORM.line_strp) return strs.line ? cstr(strs.line, u32(r)) : (u32(r), "?");
    if (form === FORM.strp) return strs.str ? cstr(strs.str, u32(r)) : (u32(r), "?");
    if (form === FORM.udata) return r.u32();
    const n = { [FORM.data1]: 1, [FORM.data2]: 2, [FORM.data4]: 4, [FORM.data8]: 8, [FORM.data16]: 16 }[form];
    if (n) { r.pos += n; return 0; }
    if (form === FORM.block) { r.pos += r.u32(); return 0; }
    throw new Error(`dwarf_lines: form 0x${form.toString(16)}`);
}

function entriesV5(r, strs) {
    const fmt = [];
    for (let n = r.u8(); n--;) fmt.push([r.u32(), r.u32()]);
    const out = [];
    for (let n = r.u32(); n--;) {
        const e = {};
        for (const [kind, form] of fmt) e[kind] = readForm(r, form, strs);
        out.push({ name: e[1], dir: e[2] ?? 0 });
    }
    return out;
}

function header(r, strs) {
    const len = u32(r), end = r.pos + len, version = u16(r);
    if (version >= 5) r.pos += 2; // address_size, segment_selector_size
    const hlen = u32(r), progStart = r.pos + hlen;
    const h = { end, version, minInst: r.u8(), maxOps: version >= 4 ? r.u8() : 1, isStmt: r.u8(),
        lineBase: (r.u8() << 24) >> 24, lineRange: r.u8(), opBase: r.u8() };
    h.stdLen = [0]; for (let i = 1; i < h.opBase; i++) h.stdLen.push(r.u8());
    if (version >= 5) { h.dirs = entriesV5(r, strs).map((e) => e.name); h.files = entriesV5(r, strs); }
    else {
        h.dirs = [""]; for (let s; (s = readForm(r, FORM.string, strs));) h.dirs.push(s);
        h.files = [null]; for (let s; (s = readForm(r, FORM.string, strs));) { h.files.push({ name: s, dir: r.u32() }); r.u32(); r.u32(); }
    }
    r.pos = progStart;
    return h;
}

function runProgram(r, h, rows) {
    let addr = 0, file = 1, line = 1;
    const emit = () => { const f = h.files[file]; rows.push([addr, f ? `${h.dirs[f.dir] ?? ""}/${f.name}` : "?", line]); };
    while (r.pos < h.end) {
        const op = r.u8();
        if (op >= h.opBase) { const a = op - h.opBase; addr += Math.floor(a / h.lineRange) * h.minInst; line += h.lineBase + (a % h.lineRange); emit(); }
        else if (op === 0) {
            const len = r.u32(), next = r.pos + len, sub = r.u8();
            if (sub === 1) { emit(); addr = 0; file = 1; line = 1; } else if (sub === 2) addr = u32(r);
            r.pos = next;
        } else if (op === 1) emit();
        else if (op === 2) addr += r.u32() * h.minInst;
        else if (op === 3) line += r.s32();
        else if (op === 4) file = r.u32();
        else if (op === 8) addr += Math.floor((255 - h.opBase) / h.lineRange) * h.minInst;
        else if (op === 9) addr += u16(r);
        else for (let k = 0; k < h.stdLen[op]; k++) r.u32();
    }
}

function customData(m, name) {
    const s = m.sections.find((x) => x.id === 0 && x.custom === name);
    if (!s) return null;
    const r = new Reader(m.buf, s.payload); r.name();
    return m.buf.subarray(r.pos, s.end);
}

// m: parseModule() of the NAMED twin. -> lookup(offset into the code section payload) -> "file:line" | null
export function lineTable(m) {
    const dl = customData(m, ".debug_line");
    if (!dl) return () => null;
    const strs = { line: customData(m, ".debug_line_str"), str: customData(m, ".debug_str") };
    const rows = [], r = new Reader(dl, 0);
    while (r.pos < dl.length) { const h = header(r, strs); runProgram(r, h, rows); r.pos = h.end; }
    // line 0 = code the compiler made up (no source line): take the last real line before it
    const real = rows.filter((x) => x[2] > 0).sort((a, b) => a[0] - b[0]);
    return (codeOffset) => {
        const a = codeOffset, rows = real;
        let lo = 0, hi = rows.length - 1, best = -1;
        while (lo <= hi) { const mid = (lo + hi) >> 1; if (rows[mid][0] <= a) { best = mid; lo = mid + 1; } else hi = mid - 1; }
        if (best < 0) return null;
        return `${rows[best][1].replace(/^.*?\/(apps|libs|rom|machine)\//, "$1/")}:${rows[best][2]}`;
    };
}
