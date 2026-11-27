"""The Track Kit as a product (R82 M7): the Blender add-on packaged as an installable Blender 5.x extension zip.

    python3 -I tools/racer/kit_pack.py -o OUT_DIR [--sample]     -> OUT_DIR/kestrel_track_kit-<version>.zip [+ kestrel_oval.blend]

The zip holds a generated `blender_manifest.toml`, a thin `__init__.py` (it puts the zip's own directory on sys.path and
registers `racer.blender`) and the add-on's modules UNCHANGED: `racer/blender/` plus every `racer` module it imports,
found by walking the imports (so a new import is bundled without a hand list, and nothing else goes in: no local import
tool, no test). Inside the extension the layout is the repository's `tools/` one, so the add-on's code needs no edit.
The version is the add-on's `bl_info["version"]` (one place). The zip is deterministic: sorted entries, a fixed date.
`--sample` also builds the sample track's `.blend` (tools/racer/tracks/sample_oval_build.py; needs Blender).
docs/ports/kestrel_racing/TRACK_KIT.md is the manual.
"""

from __future__ import annotations

import argparse
import ast
import subprocess
import sys
import zipfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
ADDON = TOOLS / "racer/blender"
MANUAL = TOOLS.parent / "docs/ports/kestrel_racing/TRACK_KIT.md"
BLENDER = Path.home() / ".local/blender/blender"
ID = "kestrel_track_kit"
LICENSE = "SPDX:LicenseRef-Pending"  # PLACEHOLDER: the licence is Matt's decision (R82 Q2, TRACK_KIT.md "Licence")
DATE = (2026, 1, 1, 0, 0, 0)

SHIM = '''"""Kestrel Racing Track Kit {version} (packaged by tools/racer/kit_pack.py). The add-on is `racer.blender`, bundled beside
this file with the pure modules it imports; the manual is TRACK_KIT.md."""

import sys
from pathlib import Path

_HERE = str(Path(__file__).resolve().parent)
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from racer import blender as _kit  # noqa: E402


def register() -> None:
    _kit.register()


def unregister() -> None:
    _kit.unregister()
'''


def version() -> str:
    """The add-on's bl_info version, read without importing bpy."""
    tree = ast.parse((ADDON / "__init__.py").read_text())
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "bl_info" for t in node.targets):
            return ".".join(str(v) for v in ast.literal_eval(node.value)["version"])
    raise SystemExit("kit_pack: no bl_info in tools/racer/blender/__init__.py")


def _module(name: str) -> Path | None:
    """tools/<name as a path>.py, or the package's __init__.py; None when it is not ours."""
    base = TOOLS.joinpath(*name.split("."))
    if base.with_suffix(".py").is_file():
        return base.with_suffix(".py")
    return base / "__init__.py" if (base / "__init__.py").is_file() else None


def _imports(path: Path) -> set[str]:
    out: set[str] = set()
    for node in ast.walk(ast.parse(path.read_text())):
        if isinstance(node, ast.ImportFrom) and node.module and node.module.split(".")[0] == "racer" and node.level == 0:
            out.add(node.module)
            out |= {f"{node.module}.{a.name}" for a in node.names}
        elif isinstance(node, ast.Import):
            out |= {a.name for a in node.names if a.name.split(".")[0] == "racer"}
    return out


def closure() -> list[Path]:
    """Every file the add-on imports, its own modules included, sorted (paths under tools/)."""
    todo = {"racer", "racer.blender"} | {f"racer.blender.{p.stem}" for p in ADDON.glob("*.py") if p.stem != "__init__"}
    seen: set[Path] = set()
    while todo:
        name = todo.pop()
        path = _module(name)
        if path is None or path in seen:
            continue
        seen.add(path)
        parts = name.split(".")
        todo |= {".".join(parts[:k]) for k in range(1, len(parts))} | _imports(path)
    return sorted(seen)


def manifest(ver: str) -> str:
    return "\n".join([
        'schema_version = "1.0.0"', f'id = "{ID}"', f'version = "{ver}"', 'name = "Kestrel Racing Track Kit"',
        'tagline = "Author tracks and cars for Kestrel Racing"', 'maintainer = "ZigMachine"', 'type = "add-on"',
        'blender_version_min = "5.3.0"', f'license = ["{LICENSE}"]', 'tags = ["Import-Export"]',
        'permissions = { files = "Write the track and car files you export" }', ""])


def _put(z: zipfile.ZipFile, name: str, data: bytes) -> None:
    info = zipfile.ZipInfo(name, DATE)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    z.writestr(info, data)


def build(out: Path) -> Path:
    ver = version()
    path = out / f"{ID}-{ver}.zip"
    files = {"blender_manifest.toml": manifest(ver).encode(), "__init__.py": SHIM.format(version=ver).encode()}
    files |= {p.relative_to(TOOLS).as_posix(): p.read_bytes() for p in closure()}
    if MANUAL.is_file():
        files["TRACK_KIT.md"] = MANUAL.read_bytes()
    with zipfile.ZipFile(path, "w") as z:
        for name in sorted(files):
            _put(z, name, files[name])
    return path


def sample(out: Path) -> Path:
    blend = out / "kestrel_oval.blend"
    subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", str(TOOLS / "racer/tracks/sample_oval_build.py"), "--",
                    str(out / "kestrel_oval.ktrk.json"), "--blend", str(blend)], check=True, capture_output=True, timeout=300)
    return blend


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-o", "--out", required=True, help="the directory the zip goes in")
    ap.add_argument("--sample", action="store_true", help="also build the sample track's .blend (needs Blender)")
    a = ap.parse_args(argv)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    path = build(out)
    print(f"kit_pack: {path} ({path.stat().st_size} bytes, {len(zipfile.ZipFile(path).namelist())} files)")
    if a.sample:
        print(f"kit_pack: {sample(out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
