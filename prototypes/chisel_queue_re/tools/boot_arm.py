"""One A/B arm's boot, the same procedure for every arm: Linux -> reboot -> U-Boot, the PL loaded
(the card's zigmachine.bit by fatload, or a local .bit sent by loadx: no card write, no JTAG),
the AFI widths as the card's boot.scr sets them (HP1 0xF00 = W64 from the first write), then the
card's own zImage/dtb/rootfs, as boot.scr does. Then glass is stopped, ready for run_glass.py.

    uv run --with pyserial --with xmodem python boot_arm.py card|LOCAL.bit [LOG]
"""
import sys
import time
import zlib
from pathlib import Path

sys.path.insert(0, "/home/matt/projects/ZigMachine/.claude/worktrees/chisel-queue-v2/fpga/tools")
import uboot_serial as us  # noqa: E402
from linux_console import LinuxConsole  # noqa: E402

BIT_AT = 0x1000000
AFI = [
    "mw.l 0xf8008000 0; mw.l 0xf8008014 0xf01; mw.l 0xf8009000 0; mw.l 0xf8009014 0xf00",
    "mw.l 0xf800a000 0; mw.l 0xf800a014 0xf01; mw.l 0xf800b000 0; mw.l 0xf800b014 0xf01",
    "md.l 0xf8009014 1",
]
LINUX = [
    "fatload mmc 0 0x2000000 zImage",
    "fatload mmc 0 0x1f00000 zigmachine.dtb",
    "fatload mmc 0 0x4000000 rootfs.cpio.uboot",
]


def to_uboot(con: us.UBoot) -> None:
    # glass off, CTRL.RUN 0 and a second for the last HP burst, before the reset reloads the PL
    con.port.write(b"\r/etc/init.d/S99glass stop; killall glass; devmem 0x43c00008 32 0; sleep 1; sync; reboot\r")
    time.sleep(3)
    con.interrupt(limit=90)


def load_pl(con: us.UBoot, bit: str, log: list[str]) -> None:
    if bit == "card":
        log.append(con.cmd(f"fatload mmc 0 {BIT_AT:#x} zigmachine.bit", timeout=60).strip()[-120:])
        log.append(con.cmd(f"fpga loadb 0 {BIT_AT:#x} ${{filesize}}", timeout=60).strip()[-120:])
        return
    data = Path(bit).read_bytes()
    t0 = time.monotonic()
    con.loadx(bit, BIT_AT)
    got, want = con.crc32(BIT_AT, len(data)), zlib.crc32(data)
    log.append(f"loadx {bit}: {len(data)} B in {time.monotonic() - t0:.0f} s, crc DDR {got:08x} file {want:08x}")
    if got != want:
        raise SystemExit("boot_arm: bitstream crc mismatch after loadx: STOP (PL not loaded)")
    log.append(con.cmd(f"fpga loadb 0 {BIT_AT:#x} {len(data):#x}", timeout=60).strip()[-120:])


def main() -> None:
    bit = sys.argv[1]
    log: list[str] = []
    con = us.UBoot("/dev/ttyUSB0", timeout=20)
    to_uboot(con)
    con.cmd("setenv bootargs console=ttyPS0,921600 earlycon rootwait")
    load_pl(con, bit, log)
    for line in AFI + LINUX:
        log.append(con.cmd(line, timeout=60).strip()[-160:])
    con.port.write(b"bootz 0x2000000 0x4000000 0x1f00000\r")
    out, end = b"", time.time() + 60
    while time.time() < end and b"login:" not in out and b"# " not in out[-200:]:
        out += con.port.read(65536)
    con.port.close()
    boot_txt = out.decode(errors="replace")
    lc = LinuxConsole()
    for _ in range(30):  # the kernel prints for ~40 s at 921600; wait until the shell answers
        time.sleep(4)
        lc.login()
        if lc.revive():
            break
    time.sleep(6)  # S99glass up
    for cmd in ["cat /proc/uptime", "devmem 0xf8009014", "touch /tmp/glass.stop; killall glass; sleep 2; ps | grep -c '[g]lass run'"]:
        log.append(f"$ {cmd}\n{lc.run(cmd, timeout=20)[1]}")
    text = "\n".join(log)
    print(text)
    if len(sys.argv) > 2:
        Path(sys.argv[2]).write_text(text + "\n\n--- boot console ---\n" + boot_txt)


if __name__ == "__main__":
    main()
