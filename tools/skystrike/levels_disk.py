"""A SKYSTRIKE disk that plays your own missions: the cart + MISSIONS.DAT + SCRNDATA.DAT.

The cart reads a disk's MISSIONS.DAT / SCRNDATA.DAT in place of its built-in
ones (apps/zig/scenes/skystrike/levels.zig), so the disk carries the same cart
as docs/demo-skystrike.zmd, ZX0-packed when zig-out/bin/zx0pack exists (a
tenth of the size; the loader takes a raw cart too).
"""
import os
import subprocess
import tempfile

from levels_model import LevelError

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
CART = os.path.join(ROOT, 'docs', 'demo-skystrike.wasm')
ZX0PACK = os.path.join(ROOT, 'zig-out', 'bin', 'zx0pack')
MKDISK = os.path.join(ROOT, 'tools', 'mkdisk.py')


def run(cmd: list[str]) -> None:
    r = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if r.returncode:
        raise LevelError(f'{os.path.basename(cmd[1] if cmd[0] == "python3" else cmd[0])} failed: '
                         f'{(r.stderr or r.stdout).strip()}')


def make_disk(files: dict[str, bytes], out: str, title: str) -> None:
    """files: {'MISSIONS.DAT': ..., 'SCRNDATA.DAT': ...} (validated by the caller)."""
    if not os.path.exists(CART):
        raise LevelError(f'no {CART}: build the cart first (./build.sh --only skystrike)')
    with tempfile.TemporaryDirectory() as tmp:
        cart = CART
        if os.access(ZX0PACK, os.X_OK):
            cart = os.path.join(tmp, 'skystrike.wasm.zx0')
            run([ZX0PACK, CART, cart])
        extra = []
        for name, data in files.items():
            path = os.path.join(tmp, name)
            open(path, 'wb').write(data)
            extra += ['--file', f'{name}={path}']
        run(['python3', MKDISK, cart, '-o', out, '--title', title, '--author', 'ZigMachine', *extra])
    print(f'{out}: {title} ({", ".join(files)}); play it: drop it on the ZigMachine page, '
          f'or open index.html?disk=<its URL>')
