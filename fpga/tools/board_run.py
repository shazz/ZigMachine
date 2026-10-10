"""One command for a board run: safe load order, firmware crc check, then the cart or a diag mode.

    sg dialout -c "uv run --with pyserial --with xmodem python fpga/tools/board_run.py \\
        --bit fpga/build/board_hp/zm_hp_gated_s1_sys80.bit --fw fpga/build/board_hp/fw_tutorial_diag5.bin \\
        [--diag 3|4] [--hp-cfg N] [--shot name] [--preflight] [--secs 5]"

Order, always: CTRL 0 + 1 s, load the PL, AFI widths, firmware to 0x04000000 (skipped when the crc
already in DDR matches), crc32 against the file's own (mismatch aborts), then cart or diag, then the
verdict. Exit 0 = PASS, 1 = FAIL, 2 = the board or console misbehaved. DO NOT run while another
session uses the board: a reload mid-burst wedges an AFI.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import zlib
from pathlib import Path

import board_diag as bd
import uboot_serial as us
from board_preflight import preflight, report
from uboot_serial import UBoot, UBootError

FW_ADDR = 0x04000000
TOOLS = Path(__file__).resolve().parent


def ensure_firmware(con: UBoot, fw: str) -> str:
    data = Path(fw).read_bytes()
    want = zlib.crc32(data)
    if con.crc32(FW_ADDR, len(data)) == want:
        return f"firmware crc {want:08x} already in DDR, upload skipped"
    con.loadx(fw, FW_ADDR)
    got = con.crc32(FW_ADDR, len(data))
    if got != want:
        raise UBootError(f"firmware crc mismatch after loadx: DDR {got:08x}, file {want:08x}: ABORT")
    return f"firmware uploaded, crc {want:08x} verified"


def take_shot(name: str) -> str:
    out = f"fpga/build/shots/{name}"
    r = subprocess.run([sys.executable, str(TOOLS / "board_shot.py"), "--out", out], capture_output=True, text=True, check=False)
    return (
        f"shot {out}.*.png" if not r.returncode else f"shot FAILED: {r.stdout.strip()[-120:]}{r.stderr.strip()[-120:]}"
    )


def board_run(con: UBoot, a: argparse.Namespace) -> tuple[bool, list[str]]:
    log: list[str] = []
    con.interrupt()
    if a.preflight:
        res = preflight(con)
        log.append("preflight " + ("PASS" if all(r.ok for r in res) else "FAIL"))
        if not all(r.ok for r in res):
            report(res)
            return False, log
        con.interrupt()
    us.quiesce(con)
    us.load_pl(a.bit)
    con.cmd("dcache off")
    us.set_afi(con)
    con.mw(bd.CTRL, 0)
    log.append(ensure_firmware(con, a.fw))
    return run_payload(con, a, log)


def run_payload(con: UBoot, a: argparse.Namespace, log: list[str]) -> tuple[bool, list[str]]:
    if a.diag:
        bd.start_diag(con, a.diag, a.hp_cfg)
        ok, note = bd.poll_diag(con, a.diag, a.secs)
        bad = bd.compare_rows(con, a.diag) if ok else []
        log += [f"diag {a.diag}: {note}", *(f"MISMATCH {b}" for b in bad)]
        ok = ok and not bad
    else:
        bd.start_cart(con)
        ok, note = bd.poll_cart(con, a.secs)
        log.append(f"cart: {note}")
    if a.shot:
        log.append(take_shot(a.shot))
    return ok, log


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--bit", required=True)
    ap.add_argument("--fw", required=True)
    ap.add_argument("--diag", type=int, choices=[3, 4])
    ap.add_argument("--hp-cfg", type=lambda s: int(s, 0), default=0, help="video_hp_cfg nibble (diag)")
    ap.add_argument("--shot", help="board_shot name under fpga/build/shots/")
    ap.add_argument("--preflight", action="store_true", help="run the hp-test preflight first")
    ap.add_argument("--secs", type=float, default=5.0, help="how long to poll")
    ap.add_argument("--tty")
    a = ap.parse_args()
    try:
        ok, log = board_run(UBoot(a.tty), a)
    except UBootError as e:
        print(f"board_run: {e}")
        return 2
    print("\n".join(log))
    print("board_run:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
