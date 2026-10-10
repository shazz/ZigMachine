"""The SAP player (libs/zig/players/sap_player.zig: the 6502 on the POKEY) through the native host
(host/sndh_oracle.c, which plays any song by its extension). A synthetic TYPE B player, assembled
here, proves the chain: writes stamped at their cycle inside the frame, WSYNC, the unknown-write
count, refusals said. The real tunes (prototypes/sap_asma, not in the repo) are skipped when absent.
With asapconv installed (a GPL renderer, run as a separate process only, never linked) an optional
check correlates the envelopes: a listening check in numbers, not bit-exactness."""

from __future__ import annotations

import itertools
import math
import os
import shutil
import struct
import subprocess
import wave
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ORACLE = FPGA / "build/host/oracle/sndh_oracle"
# The main checkout's prototypes/ (a worktree has none): git's common dir is its .git.
_MAIN = Path(
    subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        cwd=FPGA,
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()
    or FPGA.parent / ".git"
).parent
ASMA = Path(os.environ.get("ZM_SAP_DIR", str(_MAIN / "prototypes/sap_asma")))
TUNES = ["Warhawk", "Gauntlet", "Barbarian", "Ninja", "BMX_Simulator"]
PAL_HZ, FRAME = 1773447.5, 312 * 114

# INIT $3000: SKCTL = 3, AUDCTL = 0, the counter $80 = 0.
INIT = bytes.fromhex("A9038D0FD2A9008D08D2858060")
# PLAYER $3010: AUDF1 = n, AUDC1 = $AF; n++; 100 x WSYNC; AUDF3 = n, AUDC3 = $A8; CONSOL (unknown); RTS.
PLAYER = bytes.fromhex("A5808D00D2A9AF8D01D2E680A2648D0AD4CAD0FAA5808D04D2A9A88D05D28D1FD060")


def block(at: int, data: bytes) -> bytes:
    return struct.pack("<HH", at, at + len(data) - 1) + data


def synthetic(tags: str = "TYPE B\r\nINIT 3000\r\nPLAYER 3010\r\n") -> bytes:
    return b'SAP\r\nNAME "sweep"\r\n' + tags.encode() + b"\xff\xff" + block(0x3000, INIT) + block(0x3010, PLAYER)


@pytest.fixture(scope="module", autouse=True)
def oracle() -> None:
    subprocess.run(["make", "-s", "sndh-oracle"], cwd=FPGA, check=True, capture_output=True)


def play(tmp: Path, music: Path, name: str, frames: int) -> tuple[list[list[str]], str, Path]:
    """The writes ("W stamp addr data"), the console, and the PCM's path."""
    log = tmp / Path(name).stem
    env = {**os.environ, "ZM_MUSIC_DIR": str(music), "ZM_AUDIO_LOG": str(log)}
    out = subprocess.run([str(ORACLE), name, "0", str(frames)], env=env, check=True, capture_output=True, text=True)
    writes = [ln.split() for ln in log.with_suffix(".w").read_text().splitlines() if ln.startswith("W ")]
    return writes, out.stdout, log.with_suffix(".pcm")


def pokey(writes: list[list[str]], reg: int) -> list[tuple[int, int]]:
    return [(int(w[1]), int(w[3], 16)) for w in writes if int(w[2], 16) == 0x080 + 4 * reg]


def test_the_synthetic_player_writes_at_its_cycle_inside_the_frame(tmp_path: Path) -> None:
    (tmp_path / "sweep.sap").write_bytes(synthetic())
    writes, out, _ = play(tmp_path, tmp_path, "sweep.sap", 60)
    assert "ZM SAP" not in out, out  # loaded, nothing stopped
    audf1, audf3 = pokey(writes, 0), pokey(writes, 4)
    assert [v for _, v in audf1[:5]] == [0, 1, 2, 3, 4]  # PLAYER's counter, frame by frame
    assert [v for _, v in audf3[:4]] == [1, 2, 3, 4]
    frame = FRAME * 44100 / PAL_HZ  # 882.4 samples
    # AUDF3 comes 100 WSYNCs (100 lines) after AUDF1 in the same call, not at the frame's start.
    gap = 100 * 114 * 44100 / PAL_HZ
    for (t1, _), (t3, _) in zip(audf1[:5], audf3[:5], strict=True):
        assert abs((t3 - t1) - gap) <= 2, (t1, t3, gap)
    assert all(abs((b - a) - frame) <= 1 for (a, _), (b, _) in itertools.pairwise(audf1[1:20]))
    assert pokey(writes, 15)[0][1] == 3  # SKCTL out of init mode


def test_refusals_are_said_and_play_nothing(tmp_path: Path) -> None:
    for tags, why in (
        ("TYPE D\r\nINIT 3000\r\nPLAYER 3010\r\n", "TYPE not B or C"),
        ("STEREO\r\nTYPE B\r\nINIT 3000\r\nPLAYER 3010\r\n", "STEREO"),
        ("TYPE B\r\nPLAYER 3010\r\n", "a missing INIT"),
    ):
        (tmp_path / "bad.sap").write_bytes(synthetic(tags))
        writes, out, _ = play(tmp_path, tmp_path, "bad.sap", 10)
        assert f"ZM SAP refused bad.sap: {why}" in out, out
        assert not [w for w in writes if 0x080 <= int(w[2], 16) <= 0x0C0]


def test_a_jam_stops_the_tune_and_says_where(tmp_path: Path) -> None:
    data = bytearray(synthetic())
    data[data.index(INIT) + len(INIT) - 1] = 0x02  # INIT's RTS -> a JAM
    (tmp_path / "jam.sap").write_bytes(bytes(data))
    _, out, _ = play(tmp_path, tmp_path, "jam.sap", 10)
    assert "ZM SAP stopped jam.sap: cpu 1, opcode 02 at 300c" in out, out


@pytest.mark.parametrize("tune", TUNES)
def test_a_real_tune_plays_ten_seconds(tmp_path: Path, tune: str) -> None:
    if not (ASMA / f"{tune}.sap").exists():
        pytest.skip(f"{tune}.sap is not here (prototypes/sap_asma, outside the repo)")
    writes, out, pcm = play(tmp_path, ASMA, f"{tune}.sap", 600)
    assert "ZM SAP" not in out, out
    regs = {int(w[2], 16) for w in writes}
    assert {0x080, 0x084, 0x088} <= regs  # AUDF1..AUDF3 at least
    samples = struct.unpack(f"<{len(pcm.read_bytes()) // 2}h", pcm.read_bytes())[0::2]
    assert max(samples) - min(samples) > 2000  # it is not silence


def envelope(x: list[float], size: int = 1024) -> list[float]:
    return [math.sqrt(sum(v * v for v in x[i : i + size]) / size) for i in range(0, len(x) - size, size)]


def corr(a: list[float], b: list[float]) -> float:
    n = min(len(a), len(b))
    ma, mb = sum(a[:n]) / n, sum(b[:n]) / n
    num = sum((a[i] - ma) * (b[i] - mb) for i in range(n))
    return num / math.sqrt(sum((v - ma) ** 2 for v in a[:n]) * sum((v - mb) ** 2 for v in b[:n]))


@pytest.mark.skipif(
    shutil.which("asapconv") is None, reason="asapconv (the optional black-box oracle) is not installed"
)
@pytest.mark.parametrize("tune", TUNES)
def test_a_real_tune_sounds_like_asap_renders_it(tmp_path: Path, tune: str) -> None:
    if not (ASMA / f"{tune}.sap").exists():
        pytest.skip(f"{tune}.sap is not here")
    _, _, pcm = play(tmp_path, ASMA, f"{tune}.sap", 600)
    ref = tmp_path / f"{tune}.wav"
    subprocess.run(
        ["asapconv", "-t", "00:10", "-o", str(ref), str(ASMA / f"{tune}.sap")], check=True, capture_output=True
    )
    raw = pcm.read_bytes()
    ours = [float(v) for v in struct.unpack(f"<{len(raw) // 2}h", raw)[0::2]]
    with wave.open(str(ref)) as w:
        theirs = [float(v) for v in struct.unpack(f"<{w.getnframes()}h", w.readframes(w.getnframes()))]
    ea, eb = envelope(ours), envelope(theirs)
    r = max(corr(ea[lag:], eb) if lag >= 0 else corr(ea, eb[-lag:]) for lag in range(-3, 4))
    print(f"{tune}: envelope r {r:.3f}")
    assert r > 0.6
