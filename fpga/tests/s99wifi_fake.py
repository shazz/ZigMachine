"""The fake board test_s99wifi.py and test_s99wifi_usb.py run S99wifi (and its kwifi_usb) against.

The script runs under dash with busybox's own awk/find/grep/cut/tr, as on the board (not `busybox sh`:
a host busybox may prefer its own applets to PATH and run the real ip and ping); the tools that touch
the system (ip, iw, ping, dmesg, insmod, rmmod, wpa_supplicant, udhcpc, killall, logger, sleep) are
stubs that log their argv and answer from files under the fake root. sysfs and /proc are directories
under it too, so a write to `authorized` or the chipidea-usb2 driver's `unbind`/`bind` is a file.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
S99WIFI = FPGA / "glass/boot/buildroot/overlay/etc/init.d/S99wifi"
BUSYBOX_APPLETS = ["awk", "basename", "find", "grep", "cut", "tr", "cat", "mkdir", "chmod", "rm", "touch", "echo"]
TICK = "7777"  # the stub sleep ends the watch loop when it is asked to wait this long
IRQ_LINE = " 42:{:>11}          0 GIC-0  53 Level     e0002000.usb\n"

# ping: when ping_bumps_irq exists, the controller interrupts for it (a live bus); killall glass: when
# rebind_brings_wlan0 exists, the rebind brought the dongle back (glass is killed last in the rebind).
STUB = """#!/bin/sh
echo "$(basename "$0") $*" >> "$FAKE/calls"
case "$(basename "$0")" in
ip) [ "$1" = route ] && cat "$FAKE/route" 2>/dev/null ;;
ping)
    if [ -e "$FAKE/ping_bumps_irq" ]; then
        n=$(awk '{ print $2 + 4 }' "$FAKE/proc/interrupts")
        printf ' 42:%%11d          0 GIC-0  53 Level     e0002000.usb\\n' "$n" > "$FAKE/proc/interrupts"
    fi
    exit "$(cat "$FAKE/ping_rc" 2>/dev/null || echo 0)" ;;
iw) [ "$4" = power_save ] && [ "$3" = get ] && cat "$FAKE/power_save" 2>/dev/null ;;
dmesg) cat "$FAKE/dmesg" 2>/dev/null ;;
logger) shift 2; echo "$*" >> "$FAKE/syslog" ;;
insmod) [ -e "$FAKE/insmod_brings_wlan0" ] && mkdir -p "$FAKE/sys/class/net/wlan0" ;;
rmmod) [ "$1" = brcmfmac ] && rm -rf "$FAKE/sys/class/net/wlan0" ;;
killall) [ "$2" = glass ] && [ -e "$FAKE/rebind_brings_wlan0" ] && mkdir -p "$FAKE/sys/class/net/wlan0" ;;
sleep) [ "$1" = %s ] && touch "$FAKE/run/watch.stop" ;;
esac
exit 0
""" % TICK

STUBBED = ["ip", "iw", "ping", "dmesg", "insmod", "rmmod", "wpa_supplicant", "udhcpc", "killall", "logger", "sleep"]


def _usb_device(root: Path, name: str, vendor: str, product: str) -> None:
    dev = root / "sys/bus/usb/devices" / name
    dev.mkdir(parents=True)
    (dev / "idVendor").write_text(f"{vendor}\n")
    (dev / "idProduct").write_text(f"{product}\n")
    (dev / "authorized").write_text("1\n")


def make_fake(tmp_path: Path) -> Path:
    """A board with wlan0 up, the BCM43143 (0a5c:bd1e, as a HEALTHY one reads too) and a keyboard on the hub."""
    busybox = shutil.which("busybox")
    if busybox is None:
        pytest.skip("no busybox")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for applet in BUSYBOX_APPLETS:
        (bin_dir / applet).symlink_to(busybox)
    for tool in STUBBED:
        (bin_dir / tool).write_text(STUB)
        (bin_dir / tool).chmod(0o755)
    (tmp_path / "proc/sys/kernel").mkdir(parents=True)
    (tmp_path / "proc/uptime").write_text("1000.50 1999.00\n")
    (tmp_path / "sys/class/net/wlan0").mkdir(parents=True)
    _usb_device(tmp_path, "1-1.1", "0a5c", "bd1e")
    _usb_device(tmp_path, "1-1.2", "2516", "0004")
    (tmp_path / "sys/bus/platform/drivers/chipidea-usb2").mkdir(parents=True)
    (tmp_path / "kwifi").mkdir()
    for ko in ["cfg80211.ko", "brcmutil.ko", "brcmfmac.ko"]:
        (tmp_path / "kwifi" / ko).write_text("")
    (tmp_path / "wifi.conf").write_text('network={\r\n ssid="Metaverse"\r\n psk=00\r\n}\r\n')
    (tmp_path / "route").write_text("default via 192.168.0.1 dev wlan0\n192.168.0.0/24 dev wlan0\n")
    (tmp_path / "run").mkdir(mode=0o700)
    (tmp_path / "run/tick.at").write_text("")
    return tmp_path


def run(fake: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = {
        "PATH": str(fake / "bin"),
        "FAKE": str(fake),
        "KWIFI_CONF": str(fake / "wifi.conf"),
        "KWIFI_RUN": str(fake / "run"),
        "KWIFI_KMOD": str(fake / "kwifi"),
        "KWIFI_SYS": str(fake / "sys"),
        "KWIFI_PROC": str(fake / "proc"),
        "KWIFI_TICK": TICK,
        "KWIFI_MISS": "2",
        "KWIFI_WAIT": "2",
    }
    return subprocess.run(["/bin/sh", str(S99WIFI), *args], env=env, capture_output=True, text=True, timeout=30, check=False)


def calls(fake: Path) -> list[str]:
    path = fake / "calls"
    return path.read_text().splitlines() if path.exists() else []


def syslog(fake: Path) -> str:
    path = fake / "syslog"
    return path.read_text() if path.exists() else ""


def uptime(fake: Path, seconds: int) -> None:
    (fake / "proc/uptime").write_text(f"{seconds}.00 0.00\n")


def set_irqs(fake: Path, count: int) -> None:
    (fake / "proc/interrupts").write_text("           CPU0       CPU1\n" + IRQ_LINE.format(count))


def rebinds(fake: Path) -> int:
    """How many controller rebinds the watchdog started ("USB rebind N/3: why" in its log)."""
    return len(re.findall(r"^USB rebind \d/3: ", syslog(fake), re.MULTILINE))
