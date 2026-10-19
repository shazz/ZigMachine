"""The ZIGGY bench's results (fpga/cycles/native/bench), read off the board with nobody at it.

    uv run --with pyserial python fpga/tools/bench_collect.py [--tty /dev/ttyUSB0] [--load demo-bench.zmd]
        [--timeout 180] [--out fpga/build/bench]

ZIGGY has no console on the board (cycles/bboard.c prints nothing), so the cart writes its ZMBENCH
lines into a log in its own .bss (bench/log.c), and this reads it over the board's Linux shell with
busybox `devmem`, through the same uncached /dev/mem mapping of the cart window glass uses:

  1. the cart header at DDR_CART_BASE + CART_IMG_AT: "ZMCA", tag "bench", and bss_start (word 3),
     the CPU address of the log;
  2. the log's header (magic "ZMBL", done, len, lines), polled until done; with --load the disk is
     loaded first (`glass ctl load`) and a log still marked done from an earlier run is not taken;
  3. its text, a word per devmem, a shell loop per CHUNK words.

Prints the ZMBENCH lines and writes <out>/bench_<time>.txt (the lines as read) and .csv (with
cycles an op and MB/s at 100 MHz). Exit 2 if the cart is not running or never finishes.
"""

from __future__ import annotations

import argparse
import re
import csv
import struct
import sys
import time
from pathlib import Path
from typing import Protocol

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "gen"))
import glass_cart  # gen/: generated from glass/src/map_cart.zig
import glass_map

HDR_MAGIC, LOG_MAGIC = 0x41434D5A, 0x4C424D5A  # "ZMCA", "ZMBL" (bench/log.c)
BSS_START_AT, TAG_AT, LOG_HDR_WORDS = 12, 80, 4
CHUNK, MHZ = 96, 100
FIELDS = ("name", "size", "cyc", "med", "ops", "dwait", "dwr")


class Shell(Protocol):
    def run(self, cmd: str, timeout: float = 10.0) -> tuple[int, str]: ...


class NotRunning(RuntimeError):
    """The cart window holds no running bench."""


def cart_phys(cpu: int) -> int:
    return cpu - glass_map.CART_CPU_BASE + glass_map.DDR_CART_BASE


def _devmem_cmd(part: list[int]) -> str:
    """A short shell line: the tty's line buffer truncates a long address list."""
    if all(b - a == 4 for a, b in zip(part, part[1:])):
        return f"i=0; while [ $i -lt {len(part)} ]; do devmem $((0x{part[0]:08x}+4*i)); i=$((i+1)); done"
    return "for a in " + " ".join(f"0x{a:08x}" for a in part) + "; do devmem $a; done"


def read_words(sh: Shell, addrs: list[int]) -> list[int]:
    """One `devmem` a word, CHUNK words a command; every word must come back."""
    out: list[int] = []
    for i in range(0, len(addrs), CHUNK):
        part = addrs[i : i + CHUNK]
        rc, text = sh.run(_devmem_cmd(part), 30.0)
        # Only lines that are a lone hex word: the console echoes the command, addresses included.
        got = [int(ln, 16) for ln in (x.strip() for x in text.splitlines()) if re.fullmatch(r"0[xX][0-9a-fA-F]+", ln)]
        if rc != 0 or len(got) != len(part):
            raise NotRunning(f"devmem read {len(got)} of {len(part)} words (rc {rc}): {text[-120:]!r}")
        out += got
    return out


def find_log(sh: Shell) -> int:
    """The log's DDR address, from the bench cart's header."""
    base = glass_map.DDR_CART_BASE + glass_cart.CART_IMG_AT
    magic, bss, t0, t1 = read_words(sh, [base, base + BSS_START_AT, base + TAG_AT, base + TAG_AT + 4])
    tag = struct.pack("<2I", t0, t1).split(b"\0")[0]
    if magic != HDR_MAGIC or tag != b"bench":
        raise NotRunning(f"the cart window holds {tag!r} (magic {magic:#x}), not the bench")
    return cart_phys(bss)


def log_header(sh: Shell, log: int) -> tuple[int, int, int, int]:
    magic, done, length, lines = read_words(sh, [log + 4 * i for i in range(LOG_HDR_WORDS)])
    return magic, done, length, lines


def wait_done(sh: Shell, log: int, timeout: float, fresh: bool, poll: float = 2.0) -> int:
    """The log's length once done; fresh: only after it was seen running (a new run)."""
    seen_running, end = not fresh, time.monotonic() + timeout
    while time.monotonic() < end:
        magic, done, length, _ = log_header(sh, log)
        if magic == LOG_MAGIC and not done:
            seen_running = True
        if magic == LOG_MAGIC and done and seen_running:
            return length
        time.sleep(poll)
    raise NotRunning(f"the bench did not finish within {timeout:g} s")


def read_text(sh: Shell, log: int, length: int) -> str:
    first = log + 4 * LOG_HDR_WORDS
    words = read_words(sh, [first + 4 * i for i in range((length + 3) // 4)])
    return struct.pack(f"<{len(words)}I", *words)[:length].decode("ascii", "replace")


def parse(text: str) -> list[dict[str, str]]:
    """The ZMBENCH result lines as dicts (INFO and END lines are kept in the .txt only)."""
    rows = []
    for line in text.splitlines():
        if line.startswith("ZMBENCH "):
            rows.append(dict(kv.split("=", 1) for kv in line.split()[1:] if "=" in kv))
    return rows


def derived(row: dict[str, str]) -> dict[str, str]:
    """cycles an op and MB/s (bytes a cycle times the clock), from the fastest repeat."""
    cyc, ops, size = int(row["cyc"]), max(int(row["ops"]), 1), int(row["size"])
    mbs = f"{size * MHZ / cyc:.1f}" if size and cyc else ""
    return {**row, "cyc_per_op": f"{cyc / ops:.2f}", "mb_s": mbs}


def save(text: str, out: Path) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    stem = out / time.strftime("bench_%Y%m%d_%H%M%S")
    stem.with_suffix(".txt").write_text(text)
    with stem.with_suffix(".csv").open("w", newline="") as f:
        w = csv.DictWriter(f, [*FIELDS, "cyc_per_op", "mb_s"], extrasaction="ignore")
        w.writeheader()
        w.writerows(derived(r) for r in parse(text))
    return stem


def collect(sh: Shell, load: str | None, timeout: float) -> str:
    if load:
        rc, out = sh.run(f"glass ctl load {load}", 15.0)
        if rc != 0:
            raise NotRunning(f"`glass ctl load {load}` failed ({rc}): {out.strip()[-120:]}")
        time.sleep(2.0)  # the swap: the old cart's window is still there for a moment
    log = find_log(sh)
    return read_text(sh, log, wait_done(sh, log, timeout, fresh=load is not None))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--tty", help="the board's console (default $BOARD_TTY or /dev/ttyUSB0)")
    ap.add_argument("--load", help="load this shelf disk first (e.g. demo-bench.zmd)")
    ap.add_argument("--timeout", type=float, default=180.0, help="seconds to wait for the bench to finish")
    ap.add_argument("--out", type=Path, default=FPGA / "build/bench")
    a = ap.parse_args()
    from linux_console import LinuxConsole  # [lazy: pyserial only for a real board]

    con = LinuxConsole(a.tty)
    con.login()
    try:
        text = collect(con, a.load, a.timeout)
    except NotRunning as e:
        sys.exit(f"bench_collect: {e}")
    print(text, end="")
    print(f"bench_collect: {len(parse(text))} results -> {save(text, a.out)}.{{txt,csv}}", file=sys.stderr)


if __name__ == "__main__":
    main()
