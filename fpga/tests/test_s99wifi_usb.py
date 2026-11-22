"""S99wifi's USB escalation (overlay/etc/init.d/kwifi_usb, roadmap R80) against tests/s99wifi_fake.py.

21-22 Nov: the BCM43143 died during SyncTERM traffic and ~290 plain re-probes never brought it back;
then the ChipIdea EHCI (e0002000.usb) wedged, its interrupt count frozen, the keyboard dead. The fix
by hand, five times: the controller unbound and bound again, then glass restarted. The watchdog now
does that when a re-probe did not help or when the count stays still across unanswered pings, at
most once per 600 s, and gives up after 3 in a row until the gateway answers.
"""

import shutil
from pathlib import Path

import pytest

from tests.s99wifi_fake import calls, make_fake, rebinds, run, set_irqs, syslog, uptime

CI = "sys/bus/platform/drivers/chipidea-usb2"


@pytest.fixture
def fake(tmp_path: Path) -> Path:
    (tmp_path / "power_save").write_text("Power save: off\n")
    return make_fake(tmp_path)


def lose_wlan0(fake: Path) -> None:
    shutil.rmtree(fake / "sys/class/net/wlan0", ignore_errors=True)


def test_a_healthy_bd1e_dongle_never_rebinds_even_on_a_still_count(fake: Path) -> None:
    set_irqs(fake, 26410)  # the count never moves, but every ping is answered: nothing to fix
    for t in range(6):
        uptime(fake, 1000 + 30 * t)
        run(fake, "tick")
    assert rebinds(fake) == 0
    assert syslog(fake) == ""
    assert not (fake / CI / "unbind").exists()


def test_a_still_count_with_no_traffic_sent_is_an_idle_bus_not_a_wedge(fake: Path) -> None:
    (fake / "route").write_text("")  # no gateway yet: no ping, nothing the controller must answer
    (fake / "insmod_brings_wlan0").write_text("")  # the re-probe at 2 x MISS works
    set_irqs(fake, 500)
    for t in range(5):
        uptime(fake, 1000 + 30 * t)
        run(fake, "tick")
    assert "no interrupt" not in syslog(fake)
    assert rebinds(fake) == 0


def test_no_wlan0_after_a_plain_reprobe_escalates_to_the_rebind_in_the_same_look(fake: Path) -> None:
    lose_wlan0(fake)
    (fake / "rebind_brings_wlan0").write_text("")
    run(fake, "tick")
    log = syslog(fake)
    assert log.index("re-probe: still no wlan0") < log.index("USB rebind 1/3: still no wlan0 after a re-probe")
    assert (fake / CI / "unbind").read_text() == "e0002000.usb\n"
    assert (fake / CI / "bind").read_text() == "e0002000.usb\n"
    assert "killall -q glass" in calls(fake)
    assert "USB rebind: wlan0 back, joining" in log
    after = calls(fake)[calls(fake).index("killall -q glass") :]
    assert [c.split()[0] for c in after if c.split()[0] in ("ip", "wpa_supplicant", "udhcpc")] == ["ip", "wpa_supplicant", "udhcpc"]
    assert not any(c.split()[0] == "reboot" for c in calls(fake))


def test_a_minus_5_again_after_a_reprobe_rebinds_instead_of_reprobing_again(fake: Path) -> None:
    (fake / "insmod_brings_wlan0").write_text("")
    (fake / "dmesg").write_text("[ 2275.7] brcmfmac: brcmf_usb_tx_ctlpkt: Txctl wait timed out\n[ 2275.8] brcmf_cfg80211_disconnect: error (-5)\n")
    run(fake, "tick")
    assert "re-probe: driver -5" in syslog(fake) and "re-probe: wlan0 back, joining" in syslog(fake)
    assert rebinds(fake) == 0
    with (fake / "dmesg").open("a") as f:
        f.write("[ 2310.0] ieee80211 phy0: brcmf_run_escan: error (-5)\n")
    uptime(fake, 1030)  # inside REPROBE_GAP: the rebind does not wait for it
    before = len(calls(fake))
    run(fake, "tick")
    assert "USB rebind 1/3: driver -5 after a re-probe" in syslog(fake)
    assert not any(c.startswith("rmmod") for c in calls(fake)[before:])


def test_the_count_frozen_across_two_unanswered_pings_rebinds_without_touching_the_dongle(fake: Path) -> None:
    (fake / "ping_rc").write_text("1")
    (fake / "dmesg").write_text("")
    set_irqs(fake, 6185)
    run(fake, "tick")  # first look: nothing to compare with; the ping goes out
    uptime(fake, 1030)
    with (fake / "dmesg").open("a") as f:
        f.write("[ 2275.8] brcmf_cfg80211_disconnect: error (-5)\n")
    run(fake, "tick")  # still, and a new -5: held a look, no re-probe on a bus that may be wedged
    assert "no interrupt (6185) across an unanswered ping (1/2)" in syslog(fake)
    assert rebinds(fake) == 0
    uptime(fake, 1060)
    run(fake, "tick")
    assert "USB rebind 1/3: e0002000.usb interrupts frozen for 2 looks" in syslog(fake)
    assert not any(c.startswith(("rmmod", "insmod")) for c in calls(fake))
    assert (fake / "sys/bus/usb/devices/1-1.1/authorized").read_text() == "1\n"  # never re-authorized


def test_an_ap_that_is_off_rejoins_and_reprobes_but_never_rebinds(fake: Path) -> None:
    (fake / "ping_rc").write_text("1")
    (fake / "ping_bumps_irq").write_text("")  # a live bus: each ping interrupts
    (fake / "insmod_brings_wlan0").write_text("")
    set_irqs(fake, 100)
    for t in range(12):
        uptime(fake, 1000 + 100 * t)
        run(fake, "tick")
    assert syslog(fake).count("joining again") >= 2
    assert syslog(fake).count("re-probe: gateway 192.168.0.1 silent") >= 2
    assert rebinds(fake) == 0 and "no interrupt" not in syslog(fake)


def test_a_still_count_with_no_carrier_is_an_ap_gone_not_a_wedge(fake: Path) -> None:
    (fake / "ping_rc").write_text("1")
    (fake / "sys/class/net/wlan0/carrier").write_text("0\n")  # deauthenticated: the ping may not reach the bus
    (fake / "insmod_brings_wlan0").write_text("")
    set_irqs(fake, 700)
    for t in range(6):
        uptime(fake, 1000 + 30 * t)
        run(fake, "tick")
        (fake / "sys/class/net/wlan0/carrier").write_text("0\n")
    assert "no interrupt" not in syslog(fake)
    assert rebinds(fake) == 0


def no_wlan0_looks(fake: Path, start: int, step: int, n: int) -> None:
    for t in range(n):
        lose_wlan0(fake)
        uptime(fake, start + step * t)
        run(fake, "tick")


def test_rebinds_are_at_least_600_s_apart(fake: Path) -> None:
    no_wlan0_looks(fake, 1000, 30, 1)
    assert rebinds(fake) == 1
    no_wlan0_looks(fake, 1030, 30, 19)  # up to 1570 s: under REBIND_GAP after the first
    assert rebinds(fake) == 1
    assert syslog(fake).count("re-probe: no wlan0") == 1  # and no plain re-probes in between
    no_wlan0_looks(fake, 1600, 30, 1)
    assert rebinds(fake) == 2


def test_three_failed_rebinds_give_up_once_and_stop_hammering(fake: Path) -> None:
    no_wlan0_looks(fake, 1000, 600, 3)
    assert rebinds(fake) == 3
    before = len(calls(fake))
    no_wlan0_looks(fake, 2800, 600, 4)
    assert rebinds(fake) == 3
    assert syslog(fake).count("gave up: 3 USB controller rebinds") == 1
    assert not any(c.startswith(("rmmod", "insmod", "killall -q glass")) for c in calls(fake)[before:])


def test_the_gateway_answering_resets_the_count_and_the_give_up(fake: Path) -> None:
    no_wlan0_looks(fake, 1000, 600, 4)
    assert (fake / "run/gaveup").exists()
    (fake / "sys/class/net/wlan0").mkdir()  # replugged: it comes back by itself
    uptime(fake, 4000)
    run(fake, "tick")
    assert "gateway answers: Wi-Fi back (3 USB rebinds), the watchdog re-armed" in syslog(fake)
    assert not (fake / "run/gaveup").exists() and not (fake / "run/rebinds").exists()
    no_wlan0_looks(fake, 4030, 30, 1)  # new trouble: a plain re-probe first again, then rebind 1/3
    assert syslog(fake).count("re-probe: no wlan0") == 2
    assert "USB rebind 1/3: still no wlan0 after a re-probe" in syslog(fake).split("re-armed")[1]
