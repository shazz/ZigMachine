"""U-Boot recovery and trial boots: reboot into U-Boot, replay boot.cmd by hand with HP1 = HP1 and a chosen
rootfs, capture the console after bootz.  trial_boot.py ROOTFS_NAME [HP1] [SECS]
Recovery when the card's rootfs does not come up: trial_boot.py rootfs.cpio.uboot.31eeb461 0xf01"""
import sys, time
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[2] / "fpga/tools"))
import uboot_serial as us
rootfs = sys.argv[1]; hp1 = sys.argv[2] if len(sys.argv) > 2 else "0xf00"; secs = float(sys.argv[3]) if len(sys.argv) > 3 else 70
con = us.UBoot("/dev/ttyUSB0", timeout=20)
con.port.write(b"\r/etc/init.d/S99glass stop; touch /tmp/glass.stop; killall glass; devmem 0x43c00008 32 0; sleep 1; sync; reboot\r")
time.sleep(3)
con.interrupt(limit=90)
for line in [
    "setenv bootargs console=ttyPS0,921600 earlycon rootwait",
    "fatload mmc 0 0x1000000 zigmachine.bit",
    "fpga loadb 0 0x1000000 ${filesize}",
    f"mw.l 0xf8008000 0; mw.l 0xf8008014 0xf01; mw.l 0xf8009000 0; mw.l 0xf8009014 {hp1}",
    "mw.l 0xf800a000 0; mw.l 0xf800a014 0xf01; mw.l 0xf800b000 0; mw.l 0xf800b014 0xf01",
    "md.l 0xf8009014 1",
    "fatload mmc 0 0x2000000 zImage",
    "fatload mmc 0 0x1f00000 zigmachine.dtb",
    f"fatload mmc 0 0x4000000 {rootfs}",
]:
    print(con.cmd(line, timeout=60).strip()[-200:], flush=True)
con.port.write(b"bootz 0x2000000 0x4000000 0x1f00000\r")
out = b""; end = time.time() + secs
while time.time() < end:
    out += con.port.read(65536)
txt = out.decode(errors="replace")
print("\n".join(l for l in txt.splitlines() if any(k in l for k in ("glass", "HP1", "Kernel panic", "Freeing", "login", "VFS", "error", "Run /init"))))
open(sys.argv[0] + f".{rootfs}.log", "w").write(txt)
