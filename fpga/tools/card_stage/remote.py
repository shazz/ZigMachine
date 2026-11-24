"""`card.py install`: tar the staged up/ over ssh and run install.sh on the board. Only when asked."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

from .errors import CardError

HOST = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.@:-]*")
OK = "md5 check: all OK"


def up_dir(path: Path) -> Path:
    """`path` itself or its up/: whichever holds install.sh."""
    for d in (path, path / "up"):
        if (d / "install.sh").is_file() and (d / "up_list.txt").is_file():
            return d
    raise CardError(f"{path}: no staged card (install.sh + up_list.txt) here or in up/")


def install(host: str, path: Path, ssh: str = "ssh") -> str:
    """Push and run; the board's output. CardError unless every md5 checked out."""
    if not HOST.fullmatch(host):
        raise CardError(f"host {host!r}: want user@address")
    up = up_dir(path)
    tar = subprocess.Popen(["tar", "-C", str(up), "-c", "."], stdout=subprocess.PIPE)
    push = subprocess.run([ssh, host, "rm -rf /tmp/up; mkdir -p /tmp/up && tar x -C /tmp/up"], stdin=tar.stdout, check=False)
    tar.wait()
    if push.returncode or tar.returncode:
        raise CardError(f"copying {up} to {host} failed")
    run = subprocess.run([ssh, host, "sh /tmp/up/install.sh"], capture_output=True, text=True, check=False)
    print(run.stdout, end="")
    if run.returncode or OK not in run.stdout:
        raise CardError(f"install.sh on {host}: {run.stderr.strip() or 'no ' + repr(OK) + ' in its output'}")
    return run.stdout
