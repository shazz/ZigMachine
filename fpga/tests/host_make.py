"""`make` for the native hosts, under the lock the .mjs harnesses take (apps/bard_queue_check.mjs).

WHY: every host_audio build writes the same build/host/common objects (aplayer.o, machine.o, rom.o) and
gen/ headers. The gate runs several harnesses at once, so two unlocked makes rebuilt aplayer.o together:
13 Nov, mp3_player failed a push gate on this box and clang died of SIGBUS reading aplayer.o on omarchy.
make's own output is in the failure, since capture_output hid why it failed."""

from __future__ import annotations

import subprocess
from pathlib import Path

FPGA = Path(__file__).resolve().parents[1]
LOCK = FPGA / "build/bardq/make.lock"


def make_host(*targets: str) -> None:
    """`make -s TARGETS` in fpga/, one at a time across every harness of the gate."""
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    run = subprocess.run(
        ["flock", str(LOCK), "make", "-s", *targets], cwd=FPGA, capture_output=True, text=True, check=False
    )
    if run.returncode != 0:
        tail = "\n".join((run.stdout + run.stderr).splitlines()[-30:])
        raise RuntimeError(f"make {' '.join(targets)} failed ({run.returncode}):\n{tail}")
