"""Helpers for tests/test_board_bootsec.py: the browser's engine (node's WebAssembly) running
the same modules as tests/tb/bootsec_test.c, and a WAT module that exercises every opcode the
interpreter (host/wint.h) runs, each export taking and returning i64 so both sides print the
same numbers."""

from __future__ import annotations

import random
import subprocess
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
WABT = FPGA / ".tools/wabt"

# The browser's side of bootsec_test.c, line for line: the same memory, seed and imports.
NODE = r"""
import { readFileSync } from "node:fs";
const [mode, file, arg] = process.argv.slice(-3); // node -e: no script path in argv
const PAGES = 112, VBASE = 0x200000, FB = 0x1000;
const memory = new WebAssembly.Memory({ initial: PAGES, maximum: PAGES });
const mem = new Uint8Array(memory.buffer);
for (let i = 0; i < mem.length; i++) mem[i] = (i * 7) & 255;
new DataView(memory.buffer).setUint32(VBASE + 68, FB, true);
let bytes = readFileSync(file);
if (file.endsWith(".zmd")) bytes = bytes.subarray(0, 1024); // the disk's boot sector, as zmdisk.js slices it
const mod = new WebAssembly.Module(bytes);
const env = { memory, hwVideoBase: () => VBASE, beep: () => {}, id: (x) => x };
for (const imp of WebAssembly.Module.imports(mod)) if (imp.module === "env" && !(imp.name in env)) env[imp.name] = () => 0;
const fnv = () => { let h = 2166136261; for (const b of mem) h = Math.imul(h ^ b, 16777619) >>> 0; return h.toString(16).padStart(8, "0"); };
const kind = (e) => /unreachable/.test(e.message) ? "unreachable" : /out of bounds/.test(e.message) ? "oob"
    : /divi|overflow|remainder/.test(e.message) ? "div" : "trap:" + e.message;
const out = [];
if (mode === "sector") {
    let x;
    try { x = new WebAssembly.Instance(mod, { env }).exports; x.boot(); out.push(`boot ok ${fnv()}`); }
    catch (e) { out.push(`boot ${kind(e)} ${fnv()}`); x = null; }
    for (let f = 1; x && f <= Number(arg); f++) {
        x.frame(16.6);
        const rc = x.pollCartRequest && x.pollCartRequest() === 2 ? 1 : 0;
        out.push(`f ${f} ${rc} ${x.isPlaneEnabled(0) ? 1 : 0} ${fnv()}`);
        if (rc) break;
    }
} else {
    const x = new WebAssembly.Instance(mod, { env }).exports;
    for (const line of readFileSync(0, "utf8").trim().split("\n")) {
        const [name, ...args] = line.split(" ");
        try { out.push(`ok ${BigInt.asIntN(64, BigInt(x[name](...args.map(BigInt)) ?? 0))}`); }
        catch (e) { out.push(`${kind(e)} 0`); }
    }
}
console.log(out.join("\n"));
"""


def node(mode: str, file: Path, arg: str = "", stdin: str = "") -> list[str]:
    r = subprocess.run(["node", "--input-type=module", "-e", NODE, mode, str(file), arg], input=stdin,
                       capture_output=True, text=True, check=True)  # fmt: skip
    return r.stdout.strip().splitlines()


def native(exe: Path, mode: str, file: Path, arg: str = "", stdin: str = "") -> list[str]:
    argv = [str(exe), mode, str(file)] + ([arg] if arg else [])
    return subprocess.run(argv, input=stdin, capture_output=True, text=True, check=True).stdout.strip().splitlines()


I32_BIN = "add sub mul div_s div_u rem_s rem_u and or xor shl shr_s shr_u rotl rotr".split()
CMP = "eq ne lt_s lt_u gt_s gt_u le_s le_u ge_s ge_u".split()
I32_UN = "clz ctz popcnt eqz extend8_s extend16_s".split()
I64_UN = I32_UN + ["extend32_s"]
LOADS = ("i32.load i32.load8_s i32.load8_u i32.load16_s i32.load16_u i64.load i64.load8_s i64.load8_u "
         "i64.load16_s i64.load16_u i64.load32_s i64.load32_u f32.load f64.load").split()  # fmt: skip
STORES = "i32.store i32.store8 i32.store16 i64.store i64.store8 i64.store16 i64.store32 f32.store f64.store".split()


def _fn(name: str, params: int, body: str) -> str:
    return f'(func (export "{name}") (param{" i64" * params}) (result i64) {body})'


def _ops() -> list[str]:
    a, b = "(i32.wrap_i64 (local.get 0))", "(i32.wrap_i64 (local.get 1))"
    fns = [_fn(f"i32.{o}", 2, f"(i64.extend_i32_u (i32.{o} {a} {b}))") for o in I32_BIN + CMP]
    fns += [_fn(f"i64.{o}", 2, f"(i64.{o} (local.get 0) (local.get 1))") for o in I32_BIN]
    fns += [_fn(f"i64.{o}", 2, f"(i64.extend_i32_u (i64.{o} (local.get 0) (local.get 1)))") for o in CMP]
    fns += [_fn(f"i32.{o}", 1, f"(i64.extend_i32_u (i32.{o} {a}))") for o in I32_UN]
    fns += [_fn(f"i64.{o}", 1, f"(i64.extend_i32_u (i64.eqz (local.get 0)))" if o == "eqz" else f"(i64.{o} (local.get 0))")
            for o in I64_UN]  # fmt: skip
    fns += [_fn("i64.extend_i32_s", 1, f"(i64.extend_i32_s {a})"), _fn("i64.extend_i32_u", 1, f"(i64.extend_i32_u {a})")]
    return fns


def _mem() -> list[str]:
    addr = "(i32.wrap_i64 (local.get 0))"
    def as64(op: str, v: str) -> str:
        return {"i32": f"(i64.extend_i32_u {v})", "i64": v, "f32": f"(i64.extend_i32_u (i32.reinterpret_f32 {v}))",
                "f64": f"(i64.reinterpret_f64 {v})"}[op[:3]]  # fmt: skip
    def val(op: str) -> str:
        return {"i32": "(i32.wrap_i64 (local.get 1))", "i64": "(local.get 1)",
                "f32": "(f32.reinterpret_i32 (i32.wrap_i64 (local.get 1)))", "f64": "(f64.reinterpret_i64 (local.get 1))"}[op[:3]]  # fmt: skip
    fns = [_fn(f"ld.{o}", 1, as64(o, f"({o} offset=5 {addr})")) for o in LOADS]
    fns += [_fn(f"st.{o}", 2, f"({o} offset=3 {addr} {val(o)}) (i64.load offset=3 {addr})") for o in STORES]
    a3 = "(i32.wrap_i64 (local.get 0)) (i32.wrap_i64 (local.get 1)) (i32.wrap_i64 (local.get 2))"
    fns += [_fn("fill", 3, f"(memory.fill {a3}) (i64.load {addr})"), _fn("copy", 3, f"(memory.copy {a3}) (i64.load {addr})")]
    fns += [_fn("msize", 0, "(i64.extend_i32_u (memory.size))"),
            _fn("mgrow", 1, f"(i64.extend_i32_s (memory.grow {addr}))")]  # fmt: skip
    return fns


CONTROL = r"""
(func $fact (param i64) (result i64)
  (if (result i64) (i64.le_s (local.get 0) (i64.const 1)) (then (i64.const 1))
    (else (i64.mul (local.get 0) (call $fact (i64.sub (local.get 0) (i64.const 1)))))))
(func (export "fact") (param i64) (result i64) (call $fact (local.get 0)))
(func (export "loop_sum") (param i64) (result i64) (local i64)
  (block $out (loop $l (br_if $out (i64.eqz (local.get 0)))
    (local.set 1 (i64.add (local.get 1) (local.get 0)))
    (local.set 0 (i64.sub (local.get 0) (i64.const 1))) (br $l))) (local.get 1))
(func (export "brt") (param i64) (result i64)
  (block $d (block $c (block $b (block $a (br_table $a $b $c $d (i32.wrap_i64 (local.get 0))))
    (return (i64.const 10))) (return (i64.const 20))) (return (i64.const 30))) (i64.const 40))
(func (export "sel") (param i64 i64 i64) (result i64) (select (local.get 0) (local.get 1) (i32.wrap_i64 (local.get 2))))
(func (export "selt") (param i64 i64 i64) (result i64) (select (result i64) (local.get 0) (local.get 1) (i32.wrap_i64 (local.get 2))))
(func (export "mv") (param i64 i64) (result i64) (local.get 0) (local.get 1) (block (param i64 i64) (result i64) (i64.sub)))
(func (export "gcount") (param i64) (result i64) (global.set $g (i64.add (global.get $g) (local.get 0))) (global.get $g))
(func (export "callid") (param i64) (result i64) (call $id (local.get 0)))
(func (export "stub") (param i64) (result i64) (i64.extend_i32_u (call $nothere)))
(func (export "unreach") (param i64) (result i64) (if (i64.eqz (local.get 0)) (then unreachable)) (local.get 0))
(func (export "nested_if") (param i64 i64) (result i64)
  (if (result i64) (i32.wrap_i64 (local.get 0))
    (then (if (result i64) (i32.wrap_i64 (local.get 1)) (then (i64.const 1)) (else (i64.const 2))))
    (else (i64.const 3))))
(func (export "f64const") (param i64) (result i64) (i64.reinterpret_f64 (f64.const -1.5)))
(func (export "f32const") (param i64) (result i64) (i64.extend_i32_u (i32.reinterpret_f32 (f32.const 3.25))))
"""


def ops_wat() -> str:
    head = ('(module (import "env" "memory" (memory 112 112)) (import "env" "id" (func $id (param i64) (result i64)))'
            ' (import "env" "nothere" (func $nothere (result i32))) (global $g (mut i64) (i64.const 5))')  # fmt: skip
    return "\n".join([head, *_ops(), *_mem(), CONTROL, ")"])


def wat2wasm(text: str, out: Path) -> Path:
    src = out.with_suffix(".wat")
    src.write_text(text)
    subprocess.run([str(WABT / "bin/wat2wasm"), src, "-o", out], check=True)
    return out


EDGES = [0, 1, -1, 2, 7, 31, 32, 33, 63, 64, 0x7FFFFFFF, -0x80000000, 0xFFFFFFFF, 0x80000000, 2**63 - 1, -(2**63)]
MEM_EDGES = [0, 1, 3, 4, 0x200000, 0x6FFFF0, 0x6FFFF8, 0x6FFFFA, 0x6FFFFF, 0x700000, 0xFFFFFFFF, -1]


def op_calls(seed: int = 7) -> str:
    rnd = random.Random(seed)
    vals = EDGES + [rnd.randrange(-(2**63), 2**63) for _ in range(6)]
    lines = []
    for f in _ops():
        name, n = f.split('"')[1], f.count(" i64", 0, f.index("(result"))
        lines += [f"{name} {a} {b}" for a in vals for b in vals] if n == 2 else [f"{name} {a}" for a in vals]
    for o in LOADS:
        lines += [f"ld.{o} {a}" for a in MEM_EDGES]
    for o in STORES:
        lines += [f"st.{o} {a} {rnd.choice(vals)}" for a in MEM_EDGES]
    lines += [f"fill {d} {v} {n}" for d, v, n in [(16, 0xAB, 40), (0x6FFFF0, 1, 16), (0x6FFFF0, 1, 17), (0, 0, 0)]]
    lines += [f"copy {d} {s} {n}" for d, s, n in [(100, 90, 40), (90, 100, 40), (0x6FFFF0, 0, 17), (5, 0x6FFFF0, 17)]]
    lines += ["msize", "mgrow 0", "mgrow 1", "fact 20", "loop_sum 1000", "mv 9 4", "gcount 3", "gcount -10"]
    lines += [f"brt {k}" for k in (0, 1, 2, 3, 4, 99, -1)] + [f"sel 1 2 {c}" for c in (0, 1, 7)]
    lines += [f"selt 1 2 {c}" for c in (0, 1)] + ["callid 77", "stub 0", "unreach 0", "unreach 5", "f64const 0", "f32const 0"]
    lines += [f"nested_if {a} {b}" for a in (0, 1) for b in (0, 1)]
    return "\n".join(lines) + "\n"
