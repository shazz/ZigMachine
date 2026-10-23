"""zg.requestSongBytes (sfx op 8: a song image in the cart's own memory) off the song bridge
(host/audio_bridge.c) into the players (host/audio.c), as docs/sealed-loader.js's postSfx turns it
into the worklet's loadSndh / loadSap. On the board the same two files run, the bridge on ZIGGY and
the players on BARD, the mailbox between them (cycles/bsound.c waits for BARD to copy the image).

- Natively: SysInfo's SOUND page (apps/sysinfo_sound.mjs's script) reads JINKS.SND and
  GAUNTLET.SAP off its disk and plays each: mode 4 (SNDH on the 68000) and mode 5 (SAP on the
  POKEY), each heard (its samples not silent).
- The bridge alone (tests/audio_bridge_test.c): an image past the cart's memory is refused, an
  image in it is handed over with its kind and tune, the queue's order kept.
"""

from __future__ import annotations

import array
import os
import re
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
HOST = FPGA / "build/host/sysinfo/host_audio"
WABT = FPGA / ".tools/wabt"
FRAMES = 120
# SysInfo's keys (apps/sysinfo_sound.mjs): F3 the SOUND page, P plays, S stops, Down.
KEYS = ["10:key:57347", "12:key:112", "50:key:115", "52:input:1", "54:key:112", "90:key:115"]


@pytest.fixture(scope="module")
def run(tmp_path_factory: pytest.TempPathFactory) -> tuple[str, Path]:
    subprocess.run(["make", "-s", "memmap", str(HOST.relative_to(FPGA))], cwd=FPGA, check=True, capture_output=True)
    log = tmp_path_factory.mktemp("song_bytes") / "a"
    calls = [a for k in KEYS for a in ("--call", k)]
    out = subprocess.run(
        [str(HOST), "sysinfo", str(FRAMES), str(FRAMES), "--disk", str(ROOT / "docs/demo-sysinfo.zmd"), *calls],
        env={**os.environ, "ZM_AUDIO_LOG": str(log)},
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return out, log


def starts(log: Path) -> dict[str, int]:
    """Each song's first sample, by the name the bridge gave it."""
    lines = re.findall(r"^L (\d+) \d+ (\S+)$", log.with_suffix(".w").read_text(), re.MULTILINE)
    return {name: int(ts) for ts, name in lines}


def peak(log: Path, start: int, n: int) -> int:
    """The loudest sample of `n` from `start` (int16 L, R interleaved; stamps count from 0)."""
    pcm = array.array("h", log.with_suffix(".pcm").read_bytes()[4 * start : 4 * (start + n)])
    return max((abs(v) for v in pcm), default=0)


def test_the_sndh_and_the_sap_off_the_disk_load_in_their_modes(run: tuple[str, Path]) -> None:
    out, log = run
    assert re.search(r"^ZM SONG bytes bytes\.sndh 4024 mode 4$", out, re.MULTILINE), out
    assert re.search(r"^ZM SONG bytes bytes\.sap 1953 mode 5$", out, re.MULTILINE), out
    assert "ZM FX" not in out, out  # no refusal, no bad op
    assert list(starts(log)) == ["bytes.sndh", "bytes.sap"]


def test_each_is_heard_until_s_stops_it(run: tuple[str, Path]) -> None:
    _, log = run
    at = starts(log)
    assert peak(log, at["bytes.sndh"], 30 * 735) > 300, "JINKS.SND is silent"
    assert peak(log, at["bytes.sap"], 30 * 735) > 300, "GAUNTLET.SAP is silent"
    assert peak(log, 95 * 735, 20 * 735) < 50, "S did not stop the SAP"


def test_the_bridge_refuses_an_image_outside_the_carts_memory(tmp_path: Path) -> None:
    subprocess.run(["make", "-s", "memmap", "build/host/common/aplayer.h", "build/host/tutorial/cart.h"],
                   cwd=FPGA, check=True, capture_output=True)  # fmt: skip
    exe = tmp_path / "audio_bridge_test"
    inc = ["-Ihost", "-Ibuild/host/common", "-Ibuild/host/tutorial", f"-I{WABT}/share/wabt/wasm2c", f"-I{WABT}/include"]
    subprocess.run(["cc", "-std=gnu11", "-O1", "-Wall", "-Werror", *inc,
                    "tests/audio_bridge_test.c", "host/audio_bridge.c", "-o", str(exe)], cwd=FPGA, check=True)  # fmt: skip
    r = subprocess.run([str(exe)], capture_output=True, text=True, check=False)
    lines = r.stdout.splitlines()
    assert [ln for ln in lines if not ln.startswith(("ok ", "ZM FX"))] == []
    assert lines.count("ZM FX requestSongBytes out of the cart's memory") == 2
    assert sum(ln.startswith("ok ") for ln in lines) == 4 and r.returncode == 0
