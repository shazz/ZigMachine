"""U-Boot SPL's ps7_init_gpl.c, read back out of a Zynq-7000 BOOT.BIN's FSBL (docs/FPGA_GLASS.md, "Plan A").

    uv run python tools/ps7_from_bootbin.py BOOT.BIN OUT_ps7_init_gpl.c

KESTREL's SoC instantiates the bare PS7 primitive (soc/zm_board_mem.py), so no Vivado export carries a
PS7 configuration: the DDR3, clocks and MIO the board runs on today are the ones zeST's FSBL writes. A
Xilinx FSBL links Vivado's ps7_init.c, whose tables survive in the binary as words: (op << 4 | nargs),
then the arguments; a 0 ends a table. One table per stage (mio, pll, clock, ddr, peripherals,
post_config, debug) and per silicon revision (1.0, 2.0, 3.0), contiguous, and five pointers that
ps7_init() starts from (mio, pll, clock, ddr, peripherals) naming the 3.0 tables. This reads them
and writes them in U-Boot's encoding (arch/arm/mach-zynq/include/mach/ps7_init_gpl.h), so SPL replays
exactly the FSBL's register writes, without Vivado.

One deliberate change: ps7_post_config's AFI writes (0xF8008000-0xF800BFFF, HP0's 32-bit mode) are
dropped. The FSBL runs post_config after loading zeST's bitstream; SPL runs it with the PL empty, and
an AFI register touched without the PL's HP clocks hangs the ARM (FPGA_GLASS.md, Lessons 2026-10-03).
boot.cmd sets every AFI width itself, after `fpga loadb`. ps7_debug (CoreSight unlocks) is not used by
SPL and is not written.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

UNLOCK = (2, 0xF8000008, 0xDF0D)
NARGS = {1: 1, 2: 2, 3: 3, 4: 2, 5: 2}  # CLEAR, WRITE, MASKWRITE, MASKPOLL, MASKDELAY
EMIT = {2: "EMIT_WRITE", 3: "EMIT_MASKWRITE", 4: "EMIT_MASKPOLL", 5: "EMIT_MASKDELAY"}
INIT_KINDS = ("mio", "pll", "clock", "ddr", "peripherals")  # ps7_init()'s order, and the pointers'
REVS = ("1_0", "2_0", "3_0")
AFI = range(0xF8008000, 0xF800C000)

Op = tuple[int, ...]


def fsbl(boot: bytes) -> bytes:
    """The FSBL partition (boot header: 0x20 width word, 0x24 'XNLX', 0x30 offset, 0x34 length)."""
    if boot[0x20:0x28] != struct.pack("<I", 0xAA995566) + b"XNLX":
        raise ValueError("not a Zynq-7000 boot image (no width word / XNLX at 0x20)")
    off, size = struct.unpack_from("<II", boot, 0x30)
    if not 0 < off < off + size <= len(boot):
        raise ValueError(f"FSBL partition {off:#x}+{size:#x} outside the {len(boot):#x}-byte file")
    return boot[off : off + size]


def table(w: tuple[int, ...], i: int) -> tuple[list[Op], int] | None:
    """The table at word i and the index after its 0, or None if the words there are not one."""
    ops: list[Op] = []
    while i < len(w):
        op = w[i]
        if op == 0:
            return (ops, i + 1) if ops else None
        code, n = op >> 4, op & 0xF
        if NARGS.get(code) != n or i + n >= len(w):
            return None
        ops.append((code, *w[i + 1 : i + 1 + n]))
        i += 1 + n
    return None


def kind(ops: list[Op]) -> str:
    """Which stage a table is, by the registers it writes (the SLCR lock/unlock aside)."""
    addrs = {o[1] for o in ops} - {0xF8000004, 0xF8000008}
    has = lambda lo, hi: any(lo <= a <= hi for a in addrs)
    if has(0xF8006000, 0xF8006FFF):
        return "ddr"
    if has(0xF8000700, 0xF80007FF):
        return "mio"
    if has(0xE0000000, 0xE00FFFFF):
        return "peripherals"
    if any(o[0] == 4 and o[1] == 0xF800010C for o in ops):
        return "pll"
    if has(0xF8000128, 0xF80001FF):
        return "clock"
    if 0xF8000900 in addrs:
        return "post_config"
    if has(0xF8800000, 0xF89FFFFF):
        return "debug"
    raise ValueError(f"a table of {len(ops)} ops writing {sorted(hex(a) for a in addrs)[:6]}: no stage fits")


def tables(code: bytes) -> dict[str, dict[str, list[Op]]]:
    """{stage: {revision: ops}}. The tables run contiguously from the first SLCR unlock."""
    w = struct.unpack(f"<{len(code) // 4}I", code[: len(code) // 4 * 4])
    start = next((i for i in range(len(w) - 2) if w[i : i + 3] == (0x22, *UNLOCK[1:])), None)
    if start is None:
        raise ValueError("no ps7 table in the FSBL (no EMIT_WRITE(0xF8000008, 0xDF0D))")
    found: dict[str, list[tuple[int, list[Op]]]] = {}
    i = start
    while (t := table(w, i)) is not None:
        found.setdefault(kind(t[0]), []).append((i * 4, t[0]))
        i = t[1]
    by_addr = {a: k for k, ts in found.items() for a, _ in ts}
    ptrs = next((w[j : j + 5] for j in range(len(w) - 4)
                 if tuple(by_addr.get(p) for p in w[j : j + 5]) == INIT_KINDS), None)  # fmt: skip
    if ptrs is None:
        raise ValueError("no (mio, pll, clock, ddr, peripherals) pointer block naming the tables")
    out: dict[str, dict[str, list[Op]]] = {}
    for k in (*INIT_KINDS, "post_config"):
        ts = sorted(found.get(k, []))
        if len(ts) != 3:
            raise ValueError(f"{k}: {len(ts)} tables, want 3 (one per silicon revision)")
        # The 3.0 table is the one the pointer names; the linker laid all three out 1.0, 2.0, 3.0.
        if k in INIT_KINDS and ts[2][0] != ptrs[INIT_KINDS.index(k)]:
            raise ValueError(f"{k}: the 3.0 pointer {ptrs[INIT_KINDS.index(k)]:#x} is not the last table")
        out[k] = {r: ops for r, (_, ops) in zip(REVS, ts)}
    return out


def without_afi(ops: list[Op]) -> tuple[list[Op], list[Op]]:
    keep = [o for o in ops if o[1] not in AFI]
    return keep, [o for o in ops if o[1] in AFI]


def emit(name: str, ops: list[Op]) -> list[str]:
    for o in ops:
        if o[0] not in EMIT:
            raise ValueError(f"{name}: opcode {o[0]} has no U-Boot equivalent")
    lines = [f"\t{EMIT[o[0]]}({', '.join(f'0x{a:08X}U' for a in o[1:])})," for o in ops]
    return [f"unsigned long ps7_{name}[] = {{", *lines, "\tEMIT_EXIT(),", "};", ""]


def select(post: bool) -> list[str]:
    """The if/else on the silicon revision: ps7_post_config() runs a table, ps7_init() picks five."""
    heads = (
        "\tif (si_ver == PCW_SILICON_VERSION_1) {",
        "\t} else if (si_ver == PCW_SILICON_VERSION_2) {",
        "\t} else {",
    )
    out = []
    for head, rev in zip(heads, REVS, strict=True):
        body = ([f"\t\tret = ps7_config(ps7_post_config_{rev});"] if post
                else [f"\t\tps7_{k}_init_data = ps7_{k}_init_data_{rev};" for k in INIT_KINDS])  # fmt: skip
        out += [head, *body]
    return out + ["\t}"]


def source(t: dict[str, dict[str, list[Op]]], origin: str, dropped: list[Op]) -> str:
    gone = ", ".join(f"0x{o[1]:08X}" for o in dropped) or "none"
    lines = ["// SPDX-License-Identifier: GPL-2.0+",
             f"// Generated by fpga/tools/ps7_from_bootbin.py from {origin}: do not edit, do not commit",
             "// (fpga/.gitignore). The FSBL's ps7_init tables in U-Boot's encoding; post_config without",
             f"// its AFI writes ({gone}): the PL is empty when SPL runs it.",
             "#include <asm/arch/ps7_init_gpl.h>", ""]  # fmt: skip
    for rev in reversed(REVS):
        for k in INIT_KINDS:
            lines += emit(f"{k}_init_data_{rev}", t[k][rev])
        lines += emit(f"post_config_{rev}", without_afi(t["post_config"][rev])[0])
    lines += [f"unsigned long *ps7_{k}_init_data = ps7_{k}_init_data_3_0;" for k in INIT_KINDS] + [""]
    lines += ["int ps7_post_config(void)", "{", "\tunsigned long si_ver = ps7GetSiliconVersion();",
              "\tint ret;", "", *select(True), "\treturn ret;", "}", "",
              "int ps7_init(void)", "{", "\tunsigned long si_ver = ps7GetSiliconVersion();", "\tint ret;", "",
              *select(False)]  # fmt: skip
    for k in INIT_KINDS:
        lines += [f"\tret = ps7_config(ps7_{k}_init_data);", "\tif (ret != PS7_INIT_SUCCESS)", "\t\treturn ret;"]
    return "\n".join([*lines, "\treturn PS7_INIT_SUCCESS;", "}", ""])


def generate(boot: Path, out: Path) -> dict[str, dict[str, list[Op]]]:
    data = boot.read_bytes()
    t = tables(fsbl(data))
    dropped = without_afi(t["post_config"]["3_0"])[1]
    out.write_text(source(t, f"{boot.name} md5 {hashlib.md5(data).hexdigest()}", dropped))
    return t


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("boot", type=Path, help="a Zynq-7000 BOOT.BIN with a Xilinx FSBL (zeST's)")
    p.add_argument("out", type=Path, help="the ps7_init_gpl.c to write")
    a = p.parse_args()
    t = generate(a.boot, a.out)
    print(f"{a.out}: md5 {hashlib.md5(a.out.read_bytes()).hexdigest()}")
    for k, revs in t.items():
        print(f"  {k:12} " + "  ".join(f"{r} {len(ops):3} ops" for r, ops in revs.items()))


if __name__ == "__main__":
    main()
