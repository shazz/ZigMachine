"""The baker's one packer: ZX0 (zx0pack, verified bit-exact by the tool) for the sky picture, and the bake's error."""
import subprocess
from pathlib import Path


class PackError(RuntimeError):
    pass


def zx0(data, zx0pack, workdir, name="tmp.bin"):
    """The ZX0 container of `data`."""
    if not Path(zx0pack).exists():
        raise PackError(f"zx0pack not found at {zx0pack}: `zig build` installs it (docs/boot/AURORA_BOOT.md, Re-baking)")
    src, dst = Path(workdir) / name, Path(workdir) / (name + ".zx0")
    src.write_bytes(bytes(data))
    r = subprocess.run([str(zx0pack), str(src), str(dst)], capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise PackError(f"zx0pack failed: {r.stderr.strip()}")
    return dst.read_bytes()
