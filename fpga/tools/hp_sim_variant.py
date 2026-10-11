"""A board SoC sim run of one cart with a scripted mouse and another shelf disk in DDR
(tools/hp_sim_run.py --pointer / --data-disk): GEM opening ST Replay's data disk, as the
browser boots GEM for it (docs/FPGA_GLASS.md, "GEM over a data disk").

- the image is built with ZM_SIM_POINTER (cycles/board.mk), the mouse the ARM would move;
- the DDR holds the data disk where ZWINDOW puts it (tools/ddr_init.py), next to the image;
- the references play the same: scene_hash.mjs with --call F:pointer:x,y,b and --data-disk,
  the native host with ZM_GLASS_POINTER and --data-disk;
- every file of the run carries the variant's suffix, so it never answers for the plain run.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
HCYC = FPGA / "build/hcycles"
REF = FPGA / "build/cycles/ref"


def parse_pointer(text: str) -> list[tuple[int, int, int, int]]:
    """'F:x:y:b,...' -> [(frame, x, y, buttons)], frames ascending; SystemExit on a bad entry."""
    out: list[tuple[int, int, int, int]] = []
    for item in filter(None, text.split(",")):
        parts = item.split(":")
        if len(parts) != 4 or not all(p.isdigit() for p in parts):
            raise SystemExit(f"hp_sim_variant: bad --pointer entry {item!r} (want F:x:y:buttons)")
        f, x, y, b = (int(p) for p in parts)
        out.append((f, x, y, b))
    if [e[0] for e in out] != sorted(e[0] for e in out):
        raise SystemExit("hp_sim_variant: --pointer frames must ascend")
    return out


@dataclass(frozen=True)
class Variant:
    data_disk: str | None = None  # a docs/demo-<tag>.zmd mounted as a data disk
    pointer: list[tuple[int, int, int, int]] = field(default_factory=list)

    @property
    def suffix(self) -> str:
        if not self.data_disk and not self.pointer:
            return ""
        script = ",".join(":".join(map(str, e)) for e in self.pointer)
        tag = hashlib.sha256(script.encode()).hexdigest()[:8] if script else "none"
        return f"+dd-{self.data_disk or 'none'}+ptr-{tag}"

    def disk(self) -> Path | None:
        if not self.data_disk:
            return None
        path = ROOT / "docs" / f"demo-{self.data_disk}.zmd"
        if not path.exists():
            raise SystemExit(f"hp_sim_variant: no {path}")
        return path

    def sim_pointer(self) -> str:
        """ZM_SIM_POINTER / ZM_GLASS_POINTER: REG_POINTER words (x | y<<10 | buttons<<20)."""
        return ",".join(f"{f}:{x | y << 10 | b << 20:x}" for f, x, y, b in self.pointer)

    def make_vars(self) -> list[str]:
        return [f"ZM_SIM_POINTER={self.sim_pointer()}"] if self.pointer else []

    def image(self, tag: str, shelf: Path | None) -> Path:
        """The DDR image under the suffix: fw.bin (built with the mouse) + the data disk, else
        the cart's own shelf disk `shelf`, as the plain run's."""
        fw = HCYC / "sim" / tag / "fw.bin"
        out = fw.with_name(f"zm_ddr{self.suffix}.init")
        disk = self.disk() or shelf
        cmd = ["uv", "run", "python", str(FPGA / "tools/ddr_init.py"), str(fw), str(out)]
        subprocess.run([*cmd, *(["--disk", str(disk)] if disk else [])], cwd=FPGA, check=True)
        return out

    def references(self, tag: str, frames: int, every: int, disk_args: list[str]) -> None:
        """scene_hash.mjs and the native host for the same frames, the mouse and the disk."""
        disk = self.disk()
        args = ["--data-disk", str(disk)] if disk else disk_args
        calls = [a for f, x, y, b in self.pointer for a in ("--call", f"{f}:pointer:{x},{y},{b}")]
        env = {k: v for k, v in os.environ.items() if k not in ("ZM_GLASS_POINTER", "ZM_GLASS_KEYS")}
        if self.pointer:
            env["ZM_GLASS_POINTER"] = self.sim_pointer()
        REF.mkdir(parents=True, exist_ok=True)
        common = [str(frames), str(every), *args]
        runs = (("js", ["node", "apps/scene_hash.mjs", f"docs/demo-{tag}.wasm", *common, *calls]),
                ("native", [str(FPGA / f"build/host/{tag}/host"), tag, *common]))  # fmt: skip
        for kind, cmd in runs:
            out = REF / f"{tag}.{frames}.{every}.{kind}+disk{self.suffix}.json"
            with out.open("w") as f:
                subprocess.run(cmd, cwd=ROOT, env=env, stdout=f, stderr=subprocess.DEVNULL, check=False)
