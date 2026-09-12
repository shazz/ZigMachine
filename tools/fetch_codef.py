#!/usr/bin/env python3
"""Download one CODEF screen from wab.com BY ID, with everything it loads.

    python3 tools/fetch_codef.py 525
    python3 tools/fetch_codef.py 525 515 --out prototypes/codef

Why this exists: a wab screen page inlines the screen's own code in a <script>
block and loads its images from JS string tables, so neither a link-follower nor
"save page as" gets you a portable copy. This pulls the page, the inline source,
the CODEF core libraries it includes, and every asset those strings name, into
one self-contained directory per screen:

    prototypes/codef/525/
        page.html       the raw page, as served
        screen.js       the inline source, blocks concatenated with markers
        notes.md        orientation: geometry, tiles, music, assets
        manifest.json   the same, machine-readable
        lib/            the CODEF core .js the screen is written against
        assets/         font.png, main.png, raster.png, the tune, ...

Complements tools/crawl_codef.sh, which mirrors shazz's whole Remakes TREE from
untergrund. This is the by-id path for wab.com, where the demo gallery lives.

Re-runs never re-download: anything already on disk is kept (--force overrides).
prototypes/ is gitignored, so third-party reference material stays out of git.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urljoin

sys.path.insert(0, str(Path(__file__).resolve().parent))
from codef_parse import basepath_of, find_assets, inline_scripts, notes, probe  # noqa: E402

PAGE = "https://wab.com/screen.php?screen={id}"
UA = "Mozilla/5.0 (codef-fetch; +ZigMachine reference)"
TIMEOUT = 30


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


def save(path: Path, data: bytes, force: bool) -> str:
    """Write unless it is already there. Returns a one-word status for the log."""
    if path.exists() and not force:
        return "kept"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return "got"


def fetch_libs(html: str, page_url: str, sid: str, dest: Path, force: bool) -> list[str]:
    """The CODEF core the page includes — the vocabulary the screen is written in.

    A porter reading drawTile()/scrolltext_vertical needs these to learn what
    those actually DO, so they are part of the reference, not an optional extra.
    """
    import re
    libs = []
    for src in re.findall(r"<script\b[^>]*\bsrc=[\"']([^\"']+)[\"']", html, re.I):
        if "jquery" in src.lower():
            continue
        url = urljoin(page_url, src)
        if "codef" not in url and f"screens/{sid}" not in url:
            continue
        name = url.rsplit("/", 1)[-1].split("?")[0]
        try:
            print(f"   lib/{name:<30} {save(dest / 'lib' / name, get(url), force)}")
            libs.append(name)
        except urllib.error.URLError as e:
            print(f"   lib/{name:<30} FAILED ({e})")
    return libs


def fetch_assets(js: str, page_url: str, basepath: str, dest: Path,
                 force: bool) -> tuple[list[str], list[str]]:
    got, missing = [], []
    for url in find_assets(js, page_url, basepath):
        name = url.rsplit("/", 1)[-1]
        try:
            status = save(dest / "assets" / name, get(url), force)
            size = (dest / "assets" / name).stat().st_size
            print(f"   assets/{name:<27} {status} ({size} bytes)")
            got.append(name)
        except urllib.error.URLError as e:
            # A JS string table can name a file that is not actually shipped.
            # Record it rather than dying: the port may not need it.
            print(f"   assets/{name:<27} MISSING ({e})")
            missing.append(name)
    return got, missing


def fetch_screen(sid: str, out_root: Path, force: bool) -> int:
    page_url = PAGE.format(id=sid)
    dest = out_root / sid
    print(f"\n== screen {sid} -> {dest}")
    try:
        html_b = get(page_url)
    except urllib.error.URLError as e:
        print(f"   FAILED to fetch the page: {e}", file=sys.stderr)
        return 1

    html = html_b.decode("utf-8", "replace")
    print(f"   page.html      {save(dest / 'page.html', html_b, force)} ({len(html_b)} bytes)")

    js = inline_scripts(html)
    if not js.strip():
        # Not fatal: some screens are pure <iframe> or external-only. Say so
        # plainly rather than writing an empty file and looking successful.
        print("   WARNING: no inline <script> found — is this id a CODEF screen?")
    print(f"   screen.js      {save(dest / 'screen.js', js.encode(), force)} ({len(js)} bytes)")

    basepath, declared = basepath_of(js, sid)
    if not declared:
        print(f"   NOTE: no basepath in the source; assuming {basepath}")

    libs = fetch_libs(html, page_url, sid, dest, force)
    assets, missing = fetch_assets(js, page_url, basepath, dest, force)

    manifest = {"id": sid, "page": page_url, "basepath": basepath,
                "libs": libs, "assets": assets, "missing": missing, **probe(js)}
    save(dest / "manifest.json", (json.dumps(manifest, indent=2) + "\n").encode(), True)
    save(dest / "notes.md", notes(sid, manifest).encode(), True)
    print(f"   {len(assets)} asset(s), {len(missing)} missing, {len(libs)} lib(s)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Download CODEF screens from wab.com by id.")
    ap.add_argument("ids", nargs="+", help="screen id(s), e.g. 525")
    ap.add_argument("--out", default="prototypes/codef", help="destination root (gitignored)")
    ap.add_argument("--force", action="store_true", help="re-download files already present")
    a = ap.parse_args()
    root = Path(a.out)
    return max(fetch_screen(str(i), root, a.force) for i in a.ids)


if __name__ == "__main__":
    sys.exit(main())
