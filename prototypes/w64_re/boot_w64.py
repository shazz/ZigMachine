"""Reboot the board's Linux into U-Boot and replay glass/boot/boot.cmd by hand with HP1's AFI write
channel 64-bit (0xF00) from the start, so the first HP1 traffic already meets a 64-bit channel.
    boot_w64.py [HP1_WRCHAN]   (default 0xf00; 0xf01 replays boot.cmd as it is)
Serial only (no JTAG): the PL comes from the SD's zigmachine.bit via `fpga loadb`, as boot.scr does."""
import sys, time
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[2] / "fpga/tools"))
import uboot_serial as us

hp1 = sys.argv[1] if len(sys.argv) > 1 else "0xf00"
con = us.UBoot("/dev/ttyUSB0", timeout=20)
con.port.write(b"\r/etc/init.d/S99glass stop; devmem 0x43c00008 32 0; sleep 1; sync; reboot\r")
time.sleep(3)
con.interrupt(limit=90)
for line in [
    "setenv bootargs console=ttyPS0,921600 earlycon rootwait",
    "fatload mmc 0 0x1000000 zigmachine.bit",
    "fpga loadb 0 0x1000000 ${filesize}",
    f"mw.l 0xf8008000 0; mw.l 0xf8008014 0xf01; mw.l 0xf8009000 0; mw.l 0xf8009014 {hp1}",
    "mw.l 0xf800a000 0; mw.l 0xf800a014 0xf01; mw.l 0xf800b000 0; mw.l 0xf800b014 0xf01",
    "md.l 0xf8009000 6",
    "fatload mmc 0 0x2000000 zImage",
    "fatload mmc 0 0x1f00000 zigmachine.dtb",
    "fatload mmc 0 0x4000000 rootfs.cpio.uboot",
]:
    print(con.cmd(line, timeout=60).strip()[-300:])
con.port.write(b"bootz 0x2000000 0x4000000 0x1f00000\r")
print("booting")
