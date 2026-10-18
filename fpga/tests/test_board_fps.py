"""tools/board_fps.py and tools/linux_console.py against a fake board: a scripted `glass ctl`
(carts that run, trap, hang, a glass that restarts, a board that dies) and a fake serial port.
Nothing here touches the real board; time.sleep is stubbed, so the carts' seconds cost nothing."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import board_fps as bf
from linux_console import BoardSilent, LinuxConsole

RUNNING = "ZMSTAT cart={c} fps=59.9 frame_ms=16.6 bard=12/30 player=BARD:SNDH_68k state=running frames=299 secs=5.0 missed=1 beat=600 trap=- err=- song=Wings of Death"


def zmstat(cart: str, state: str) -> str:
    return RUNNING.format(c=cart).replace("state=running", f"state={state}")


class FakeConsole:
    """`glass ctl` answers by cart: 'ok' runs, 'silent' fails its load, 'hang' stalls, 'dead' kills the board."""

    def __init__(self, carts: dict[str, str], glass_down: int = 0) -> None:
        self.carts, self.glass_down, self.sent = carts, glass_down, []
        self.current = ""

    def run(self, cmd: str, timeout: float = 10.0) -> tuple[int, str]:
        self.sent.append(cmd)
        args = cmd.removeprefix("glass ctl ").split()
        if self.glass_down:
            self.glass_down -= 1
            return 3, "glass ctl: NoGlass"
        if args[0] == "list":
            return 0, "".join(f"{c}\tTitle {c}\n" for c in self.carts) + f"ok {len(self.carts)} disks"
        if args[0] == "load":
            self.current = args[1]
            if self.carts[self.current] == "dead":
                raise BoardSilent("no reply")
            if self.carts[self.current] == "silent":
                return 1, f"err {self.current}: CartSilent"
            return 0, f"ok {self.current} running, loaded in 2600 ms"
        if args[0] == "stats":
            state = {"ok": "running", "silent": "silent", "hang": "stalled"}[self.carts[self.current]]
            return 0, "[glass] a log line\n" + zmstat(self.current, state)
        return 0, "ok"

    def revive(self) -> bool:
        return False


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(bf.time, "sleep", lambda s: None)


def args(**kw: object) -> argparse.Namespace:
    return argparse.Namespace(**({"secs": 0.0, "window": 5} | kw))


def test_parse_zmstat_takes_every_field_and_the_song_with_its_spaces() -> None:
    row = bf.parse_zmstat("junk\n" + zmstat("a.zmd", "running") + "\n")
    assert row is not None
    assert (row["cart"], row["fps"], row["frame_ms"], row["bard"]) == ("a.zmd", "59.9", "16.6", "12/30")
    assert (row["player"], row["state"], row["missed"], row["song"]) == (
        "BARD:SNDH_68k",
        "running",
        "1",
        "Wings of Death",
    )
    assert bf.parse_zmstat("ok a.zmd running") is None


def test_parse_keys_orders_steps_and_rejects_a_malformed_one() -> None:
    keys = bf.parse_keys("# comment\ndemo-union.zmd 4:space 2:1:down  # trailing\n\njoust.zmd 1:joy=fire 1.5:joy=0\n")
    assert [(s.at, s.ctl) for s in keys["demo-union.zmd"]] == [(2.0, "key 1 down"), (4.0, "key space tap")]
    assert [s.ctl for s in keys["joust.zmd"]] == ["joy fire", "joy 0"]
    with pytest.raises(ValueError, match="line 1"):
        bf.parse_keys("a.zmd 2")


def test_run_measures_every_cart_and_moves_past_a_silent_and_a_hung_one(tmp_path: Path) -> None:
    con = FakeConsole({"a.zmd": "ok", "b.zmd": "silent", "c.zmd": "hang", "d.zmd": "ok"})
    g = bf.Glass(con)  # type: ignore[arg-type]  # [fake: duck-typed LinuxConsole]
    keys = {"a.zmd": [bf.Step(0.0, "key 1 tap")]}
    assert bf.run(g, bf.shelf(g), keys, args(), tmp_path) == 0
    assert "glass ctl key 1 tap" in con.sent
    assert con.sent.count("glass ctl quit-cart") == 1  # only the hung cart
    csv_text = next(tmp_path.glob("*.csv")).read_text().splitlines()
    assert csv_text[0] == ",".join(bf.FIELDS)
    assert [ln.split(",")[7] for ln in csv_text[1:]] == ["running", "silent", "stalled", "running"]
    md = next(tmp_path.glob("*.md")).read_text()
    assert "| a.zmd | 59.9 | 16.6 | 299 | 1 | 12/30 | BARD:SNDH_68k | running | - | Wings of Death |" in md


def test_a_board_that_stops_answering_stops_the_run_with_what_was_measured(tmp_path: Path) -> None:
    con = FakeConsole({"a.zmd": "ok", "b.zmd": "dead", "c.zmd": "ok"})
    g = bf.Glass(con)  # type: ignore[arg-type]  # [fake: duck-typed LinuxConsole]
    assert bf.run(g, ["a.zmd", "b.zmd", "c.zmd"], {}, args(), tmp_path) == 2
    md = next(tmp_path.glob("*.md")).read_text()
    assert "| a.zmd |" in md and "c.zmd" not in md
    assert "STOPPED at b.zmd (1/3 measured): the board stopped answering" in md


def test_a_restarting_glass_is_waited_for_and_one_that_never_returns_aborts() -> None:
    con = FakeConsole({"a.zmd": "ok"}, glass_down=2)
    assert bf.shelf(bf.Glass(con)) == ["a.zmd"]  # type: ignore[arg-type]  # [fake]
    gone = FakeConsole({"a.zmd": "ok"}, glass_down=100)
    with pytest.raises(bf.Abort, match="glass stopped answering"):
        bf.shelf(bf.Glass(gone))  # type: ignore[arg-type]  # [fake]


class FakePort:
    def __init__(self, reply: bytes) -> None:
        self.reply, self.written = reply, b""

    def write(self, b: bytes) -> None:
        self.written += b

    def read(self, n: int) -> bytes:
        out, self.reply = self.reply, b""
        return out

    def reset_input_buffer(self) -> None:
        pass


def test_linux_console_returns_the_output_between_the_echo_and_the_marker() -> None:
    port = FakePort(b'glass ctl stats; echo "@@ZM1 $?@@"\r\nZMSTAT cart=a.zmd\r\n@@ZM1 0@@\r\n# ')
    con = LinuxConsole(port=port)
    assert con.run("glass ctl stats") == (0, "ZMSTAT cart=a.zmd")
    assert port.written == b'glass ctl stats; echo "@@ZM1 $?@@"\r'
    with pytest.raises(BoardSilent):
        con.run("true", timeout=0.05)
