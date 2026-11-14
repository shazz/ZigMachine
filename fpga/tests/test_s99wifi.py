"""S99wifi's join and watchdog (fpga/glass/boot/buildroot/overlay/etc/init.d/S99wifi) against fakes.

The board's dongle died twice on 14 Nov (wlan0 gone; joined but deaf with power save on). The script
runs under dash with busybox's own awk/find/grep/cut/tr, as on the board (not `busybox sh`: a host
busybox may prefer its own applets to PATH and run the real ip and ping); the tools that touch
the system (ip, iw, ping, dmesg, insmod, rmmod, wpa_supplicant, udhcpc, killall, logger, sleep) are
stubs that log their argv and answer from files under the fake root.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
S99WIFI = FPGA / "glass/boot/buildroot/overlay/etc/init.d/S99wifi"
BUSYBOX_APPLETS = ["awk", "basename", "find", "grep", "cut", "tr", "cat", "mkdir", "chmod", "rm", "touch", "echo"]
TICK = "7777"  # the stub sleep ends the watch loop when it is asked to wait this long

STUB = """#!/bin/sh
echo "$(basename "$0") $*" >> "$FAKE/calls"
case "$(basename "$0")" in
ip) [ "$1" = route ] && cat "$FAKE/route" 2>/dev/null ;;
ping) exit "$(cat "$FAKE/ping_rc" 2>/dev/null || echo 0)" ;;
iw) [ "$4" = power_save ] && [ "$3" = get ] && cat "$FAKE/power_save" 2>/dev/null ;;
dmesg) cat "$FAKE/dmesg" 2>/dev/null ;;
logger) shift 2; echo "$*" >> "$FAKE/syslog" ;;
insmod) [ -e "$FAKE/insmod_brings_wlan0" ] && mkdir -p "$FAKE/sys/class/net/wlan0" ;;
rmmod) [ "$1" = brcmfmac ] && rm -rf "$FAKE/sys/class/net/wlan0" ;;
sleep) [ "$1" = %s ] && touch "$FAKE/run/watch.stop" ;;
esac
exit 0
""" % TICK


@pytest.fixture
def fake(tmp_path: Path) -> Path:
    busybox = shutil.which("busybox")
    if busybox is None:
        pytest.skip("no busybox")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for applet in BUSYBOX_APPLETS:
        (bin_dir / applet).symlink_to(busybox)
    for tool in ["ip", "iw", "ping", "dmesg", "insmod", "rmmod", "wpa_supplicant", "udhcpc", "killall", "logger", "sleep"]:
        (bin_dir / tool).write_text(STUB)
        (bin_dir / tool).chmod(0o755)
    (tmp_path / "proc/sys/kernel").mkdir(parents=True)
    (tmp_path / "proc/uptime").write_text("1000.50 1999.00\n")
    (tmp_path / "sys/class/net/wlan0").mkdir(parents=True)
    dongle = tmp_path / "sys/bus/usb/devices/1-1.1"
    dongle.mkdir(parents=True)
    (dongle / "idVendor").write_text("0a5c\n")
    (dongle / "idProduct").write_text("bd1e\n")
    (dongle / "authorized").write_text("1\n")
    keyboard = tmp_path / "sys/bus/usb/devices/1-1.2"
    keyboard.mkdir()
    (keyboard / "idVendor").write_text("2516\n")
    (keyboard / "authorized").write_text("1\n")
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


def test_start_joins_turns_power_save_off_and_watches(fake: Path) -> None:
    r = run(fake, "start")
    assert r.returncode == 0, r.stderr
    log = calls(fake)
    order = [c.split()[0] for c in log if c.split()[0] in ("ip", "wpa_supplicant", "iw", "udhcpc")]
    assert order[:4] == ["ip", "wpa_supplicant", "iw", "udhcpc"]
    assert "iw dev wlan0 set power_save off" in log
    assert (fake / "run/wpa.conf").read_text() == 'network={\n ssid="Metaverse"\n psk=00\n}\n'
    assert oct((fake / "run/wpa.conf").stat().st_mode & 0o777) == "0o600"
    for _ in range(100):  # the watch loop: one sleep, then the stub stops it
        if (fake / "run/watch.stop").exists():
            break
        subprocess.run(["sleep", "0.05"], check=True)
    assert (fake / "run/watch.stop").exists()


def test_start_without_wifi_conf_does_nothing(fake: Path) -> None:
    (fake / "wifi.conf").unlink()
    r = run(fake, "start")
    assert r.returncode == 0
    assert calls(fake) == []


def test_a_gateway_that_answers_is_left_alone(fake: Path) -> None:
    (fake / "power_save").write_text("Power save: off\n")
    run(fake, "tick")
    assert (fake / "run/miss").read_text().strip() == "0"
    assert not [c for c in calls(fake) if c.startswith(("wpa_supplicant", "rmmod", "insmod"))]
    assert syslog(fake) == ""


def test_power_save_found_on_again_is_turned_off_and_logged(fake: Path) -> None:
    (fake / "power_save").write_text("Power save: on\n")
    run(fake, "tick")
    assert "iw dev wlan0 set power_save off" in calls(fake)
    assert "power save was on again" in syslog(fake)


def test_a_silent_gateway_rejoins_after_miss_ticks_then_reprobes(fake: Path) -> None:
    (fake / "ping_rc").write_text("1")
    run(fake, "tick")
    assert not any(c.startswith("wpa_supplicant") for c in calls(fake))  # one silent tick: nothing yet
    run(fake, "tick")
    assert sum(c.startswith("wpa_supplicant") for c in calls(fake)) == 1  # MISS=2: join again
    assert "joining again" in syslog(fake)
    run(fake, "tick")
    assert not any(c.startswith("rmmod") for c in calls(fake))
    (fake / "insmod_brings_wlan0").write_text("")
    run(fake, "tick")  # 2*MISS silent: the dongle off the bus and back
    assert any(c.startswith("rmmod brcmfmac") for c in calls(fake))
    assert "re-probe: gateway 192.168.0.1 silent for 4 ticks" in syslog(fake)
    assert "USB 1-1.1 (0a5c:bd1e) re-authorized" in syslog(fake)
    assert (fake / "sys/bus/usb/devices/1-1.1/authorized").read_text().strip() == "1"
    assert (fake / "run/miss").read_text().strip() == "0"
    assert sum(c.startswith("wpa_supplicant") for c in calls(fake)) == 2  # joined again after it


def test_no_wlan0_reprobes_but_not_twice_within_the_gap(fake: Path) -> None:
    shutil.rmtree(fake / "sys/class/net/wlan0")
    run(fake, "tick")
    assert "re-probe: no wlan0" in syslog(fake)
    assert "re-probe: still no wlan0" in syslog(fake)
    assert (fake / "proc/sys/kernel/modprobe").read_text().strip().endswith("kwifi/modprobe")
    before = len(calls(fake))
    uptime(fake, 1100)  # 100 s later: under REPROBE_GAP (300)
    run(fake, "tick")
    assert not any(c.startswith("rmmod") for c in calls(fake)[before:])
    uptime(fake, 1400)
    (fake / "insmod_brings_wlan0").write_text("")
    run(fake, "tick")
    assert "re-probe: wlan0 back, joining" in syslog(fake)
    assert (fake / "sys/class/net/wlan0").exists()


def test_a_driver_eio_reprobes_and_an_unrelated_minus_52_does_not(fake: Path) -> None:
    (fake / "dmesg").write_text("[ 14.1] ieee80211 phy0: brcmf_inetaddr_changed: fail to get arp ip table err:-52\n")
    run(fake, "tick")
    assert "re-probe" not in syslog(fake)
    (fake / "insmod_brings_wlan0").write_text("")
    with (fake / "dmesg").open("a") as f:
        f.write("[ 9999.0] brcmfmac: brcmf_usb_tx_ctlpkt: err -5\n")
    run(fake, "tick")
    assert "the driver logged -5" in syslog(fake)
    assert "re-probe: driver -5" in syslog(fake)
    assert not any(c.split()[0] == "reboot" for c in calls(fake))


def test_an_osd_join_under_way_and_a_forgotten_network_are_left_alone(fake: Path) -> None:
    (fake / "ping_rc").write_text("1")
    os.utime(fake / "run/tick.at", (1, 1))
    (fake / "run/osd.log").write_text("Successfully initialized wpa_supplicant\n")
    run(fake, "tick")
    assert calls(fake) == []  # glass's join owns wpa_supplicant now
    (fake / "wifi.conf").unlink()
    run(fake, "tick")
    run(fake, "tick")
    assert calls(fake) == []
