"""S99wifi's join and watchdog (fpga/glass/boot/buildroot/overlay/etc/init.d/S99wifi) against fakes.

The board's dongle died twice on 14 Nov (wlan0 gone; joined but deaf with power save on). The fake
board is tests/s99wifi_fake.py's; the USB controller side (R80) is test_s99wifi_usb.py's.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

from tests.s99wifi_fake import calls, make_fake, run, syslog, uptime


@pytest.fixture
def fake(tmp_path: Path) -> Path:
    return make_fake(tmp_path)


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


def test_a_minus_5_already_in_the_boot_log_is_not_news_to_the_watchdog(fake: Path) -> None:
    (fake / "dmesg").write_text("[ 5.3] brcmfmac: brcmf_usb_dl_cmd: err -5, then the probe came up\n")
    (fake / "power_save").write_text("Power save: off\n")
    run(fake, "start")
    assert (fake / "run/eio").read_text().strip() == "1"  # seeded at start
    run(fake, "tick")
    assert "re-probe" not in syslog(fake) and "-5" not in syslog(fake)
    assert not any(c.startswith("rmmod") for c in calls(fake))


def test_not_connected_is_not_power_save_on(fake: Path) -> None:
    (fake / "power_save").write_text("Not connected.\n")
    run(fake, "tick")
    assert "iw dev wlan0 set power_save off" not in calls(fake)


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


def test_no_wlan0_reprobes_then_waits_the_gap_when_the_dongle_is_off_the_bus(fake: Path) -> None:
    # No Broadcom device on the bus (unplugged): plain re-probes as before, never a controller rebind.
    shutil.rmtree(fake / "sys/class/net/wlan0")
    shutil.rmtree(fake / "sys/bus/usb/devices/1-1.1")
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
    assert "USB rebind" not in syslog(fake)


def test_a_driver_eio_reprobes_and_an_unrelated_minus_52_does_not(fake: Path) -> None:
    (fake / "dmesg").write_text("[ 14.1] ieee80211 phy0: brcmf_inetaddr_changed: fail to get arp ip table err:-52\n")
    run(fake, "tick")
    assert "re-probe" not in syslog(fake)
    assert (fake / "run/eio").read_text().strip() == "0"
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
