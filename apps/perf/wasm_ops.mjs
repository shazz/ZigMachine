// Instruction decoding for the perf tools: immediates, stack effect, op class.
// Opcodes are numbers; the 0xFC prefix family is 0xFC00 | sub-opcode.
// Covers MVP + sign-extension + saturating truncation + bulk memory + reference types
// + multi-memory memargs (what Zig, clang and rustc emit for wasm32 today). SIMD (0xFD)
// is rejected loudly: a cart using it would need the table extended, not guessed.

export const OP = {
    unreachable: 0x00, nop: 0x01, block: 0x02, loop: 0x03, if: 0x04, else: 0x05, end: 0x0b,
    br: 0x0c, br_if: 0x0d, br_table: 0x0e, return: 0x0f, call: 0x10, call_indirect: 0x11,
    drop: 0x1a, select: 0x1b, local_get: 0x20, local_set: 0x21, local_tee: 0x22,
    global_get: 0x23, global_set: 0x24, i32_const: 0x41, i64_const: 0x42, f32_const: 0x43, f64_const: 0x44,
    memory_copy: 0xfc0a, memory_fill: 0xfc0b,
};

const isMemarg = (op) => op >= 0x28 && op <= 0x3e;
export const isLoad = (op) => op >= 0x28 && op <= 0x35;
export const isStore = (op) => op >= 0x36 && op <= 0x3e;
// bytes written by each store opcode
export const STORE_WIDTH = { 0x36: 4, 0x37: 8, 0x38: 4, 0x39: 8, 0x3a: 1, 0x3b: 2, 0x3c: 1, 0x3d: 2, 0x3e: 4 };
// bytes read by each load opcode
export const LOAD_WIDTH = {
    0x28: 4, 0x29: 8, 0x2a: 4, 0x2b: 8, 0x2c: 1, 0x2d: 1, 0x2e: 2, 0x2f: 2,
    0x30: 1, 0x31: 1, 0x32: 2, 0x33: 2, 0x34: 4, 0x35: 4,
};

function blockType(r) {
    const b = r.buf[r.pos];
    if (b === 0x40 || (b >= 0x6f && b <= 0x7f)) { r.pos++; return b; }
    return r.u32() + 0x1000; // a type index
}

function memarg(r) {
    const align = r.u32();
    const mem = align & 0x40 ? r.u32() : 0;
    return { align: align & 0x3f, mem, offset: r.u32() };
}

const FC_IMM = { 8: (r) => [r.u32(), r.u32()], 9: (r) => [r.u32()], 10: (r) => [r.u32(), r.u32()], 11: (r) => [r.u32()],
    12: (r) => [r.u32(), r.u32()], 13: (r) => [r.u32()], 14: (r) => [r.u32(), r.u32()],
    15: (r) => [r.u32()], 16: (r) => [r.u32()], 17: (r) => [r.u32()] };

// Decode one instruction at r.pos. Returns { op, imm } (imm shape depends on op).
export function decode(r) {
    let op = r.u8();
    if (op === 0xfc) {
        const sub = r.u32();
        op = 0xfc00 | sub;
        return { op, imm: sub < 8 ? null : FC_IMM[sub](r) };
    }
    if (op === 0xfd) throw new Error("wasm_ops: SIMD (0xFD) not supported");
    if (op === 0x02 || op === 0x03 || op === 0x04) return { op, imm: blockType(r) };
    if (op === 0x0c || op === 0x0d) return { op, imm: r.u32() };
    if (op === 0x0e) { const ls = []; for (let n = r.u32(); n--;) ls.push(r.u32()); return { op, imm: [ls, r.u32()] }; }
    if (op === 0x10 || op === 0x12 || op === 0xd2) return { op, imm: r.u32() };
    if (op === 0x11 || op === 0x13) return { op, imm: [r.u32(), r.u32()] };
    if (op === 0x1c) { const ts = []; for (let n = r.u32(); n--;) ts.push(r.u8()); return { op, imm: ts }; }
    if (op >= 0x20 && op <= 0x26) return { op, imm: r.u32() };
    if (isMemarg(op)) return { op, imm: memarg(r) };
    if (op === 0x3f || op === 0x40) return { op, imm: r.u32() };
    if (op === 0x41) return { op, imm: r.s32() };
    if (op === 0x42) { r.s64(); return { op, imm: null }; }
    if (op === 0x43) { r.pos += 4; return { op, imm: null }; }
    if (op === 0x44) { r.pos += 8; return { op, imm: null }; }
    if (op === 0xd0) { r.u8(); return { op, imm: null }; }
    if (op <= 0x01 || (op >= 0x05 && op <= 0x0b) || op === 0x0f || op === 0x1a || op === 0x1b
        || (op >= 0x45 && op <= 0xc4) || op === 0xd1) return { op, imm: null };
    throw new Error(`wasm_ops: unknown opcode 0x${op.toString(16)} at ${r.pos - 1}`);
}

// [pops, pushes] for straight-line producer tracking; calls are resolved by the caller.
export function stackEffect(op) {
    if (op >= 0x45 && op <= 0xc4) {
        const unary = op === 0x45 || op === 0x50 || (op >= 0x67 && op <= 0x69) || (op >= 0x79 && op <= 0x7b)
            || (op >= 0x8b && op <= 0x91) || (op >= 0x99 && op <= 0x9f) || op >= 0xa7;
        return unary ? [1, 1] : [2, 1];
    }
    if (isLoad(op)) return [1, 1];
    if (isStore(op)) return [2, 0];
    if (op >= 0x41 && op <= 0x44) return [0, 1];
    if (op === 0x20 || op === 0x23 || op === 0x3f) return [0, 1];
    if (op === 0x21 || op === 0x24 || op === 0x1a || op === 0x0d || op === 0x04) return [1, 0];
    if (op === 0x22 || op === 0x40) return [1, 1];
    if (op === 0x1b || op === 0x1c) return [3, 1];
    if (op >= 0xfc00 && op <= 0xfc07) return [1, 1];
    if (op === 0xfc0a || op === 0xfc0b || op === 0xfc08) return [3, 0];
    return [0, 0];
}
