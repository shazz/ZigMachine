"""LOCAL ONLY: the 68000 code shapes the 32X decoders find their tables by (vr32x_pan.py, vr32x_objects.py).

The shapes are bytes of the cartridge's own code, so they are NOT in the repository: they live in a git-ignored JSON file
beside the user's dump (DEFAULT; `vr32x_import.py --signatures`), {name: "hex bytes, '..' = any byte"}, and a decoder
is handed the loaded dict. A missing file or a missing name is an error with the path, never a silent skip. The tests
use synthetic shapes of the same layout. This file holds no data.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

DEFAULT = Path("prototypes/racer_re/vr_local/32x/signatures.json")  # under the repository root, git-ignored
PAN = ("TILE_LIST", "NAME_LIST", "KOS_JOBS", "ENI_JOBS", "CRAM_LIST")  # vr32x_pan's
OBJECTS = ("GANTRY", "DISPATCH", "PAIR", "LOOP", "IMM", "ROLL")  # vr32x_objects'
Sigs = dict[str, str]


class SigError(ValueError):
    pass


def load(path: Path, names: tuple[str, ...] = PAN + OBJECTS) -> Sigs:
    """The code shapes in `path` (each of `names` required, each a hex shape)."""
    if not path.is_file():
        raise SigError(f"{path}: no signatures file (LOCAL, git-ignored: the 68000 code shapes the 32X tables are found "
                       "by; pass --signatures <file>)")
    try:
        sigs = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise SigError(f"{path}: not JSON ({e})") from e
    if not isinstance(sigs, dict):
        raise SigError(f"{path}: want an object of name -> shape")
    missing = [n for n in names if not isinstance(sigs.get(n), str)]
    if missing:
        raise SigError(f"{path}: no shape for {', '.join(missing)}")
    for n in names:
        pattern(sigs[n])
    return {n: sigs[n] for n in names}


def pattern(code: str) -> re.Pattern[bytes]:
    """A shape ("hex bytes, '..' = any byte", spaces ignored) as a bytes regex."""
    text = code.replace(" ", "")
    toks = re.findall(r"\.\.|[0-9a-fA-F]{2}", text)
    if "".join(toks) != text or not toks:
        raise SigError(f"shape {code!r}: want hex bytes and '..' only")
    return re.compile(b"".join(b"." if t == ".." else re.escape(bytes.fromhex(t)) for t in toks), re.DOTALL)
