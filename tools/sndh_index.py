#!/usr/bin/env python3
"""Searchable index of the local SNDH archive — find a tune by NAME.

    python3 tools/sndh_index.py --build            # scan the archive (once)
    python3 tools/sndh_index.py bmx                # search title/composer/path
    python3 tools/sndh_index.py "leaving terramis" # fuzzy: finds "Leavin Teramis"

Why: picking a screen's music means going from a title to a file, and the archive
holds ~5900 tunes across ~680 composer directories. `find -iname` searches
FILENAMES, which is how "Leaving Terramis" was once reported missing — the file
is `Leavin_Teramis.sndh` (one 'r') but its TITL tag reads "Leavin Teramis". This
indexes the tags, so a title search finds it whatever the file is called.

Two fields here that a plain name index would not carry, because they decide
whether a tune is usable at all on this machine:

  flag      `~a` means STE DMA samples, which the SNDH player does NOT emulate:
            the tune loads clean and plays SILENCE. `~y` and `~dy` are fine.
  subtunes  an SNDH can hold many songs (Leavin Teramis holds 11); a scene picks
            one with zg.requestSongTune(name, n), counting from 1.

Tag extraction follows the approach in ~/projects/MCPHatari/db/generate.py, which
indexes the same archive for the opposite lookup (bytes -> name, to identify a
tune playing in RAM). This one is name -> file, for choosing one.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from difflib import SequenceMatcher
from pathlib import Path

# Anchored to the REPO, not the cwd: the tool is run from subdirectories and
# from agents with their own working directory, and a cwd-relative path made it
# claim the index was missing and demand --build.
REPO = Path(__file__).resolve().parent.parent
ARCHIVE = REPO / "prototypes/sndh_lf"
INDEX = REPO / "prototypes/sndh_index.json"
HEAD = 512  # tags live in the header; no need to read whole files


def tag_str(buf: bytes, tag: bytes) -> str:
    """A NUL-terminated string tag (TITL/COMM/YEAR/FLAG)."""
    p = buf.find(tag, 12, HEAD)
    if p == -1:
        return ""
    e = buf.find(b"\0", p + len(tag))
    if e == -1:
        return ""
    return buf[p + len(tag):e].decode("latin-1", "replace").strip()


def subtune_count(buf: bytes) -> int:
    """The `##NN` tag. Absent means a single song."""
    m = re.search(rb"##(\d\d)", buf[:HEAD])
    return int(m.group(1)) if m else 1


def build() -> int:
    files = sorted(ARCHIVE.rglob("*.sndh"))
    if not files:
        sys.exit(f"no .sndh under {ARCHIVE} — is the archive present?")
    out = []
    for p in files:
        buf = p.open("rb").read(HEAD)
        if b"SNDH" not in buf[:64]:
            continue  # packed or not an SNDH image; skip rather than guess
        out.append({
            "title": tag_str(buf, b"TITL"),
            "composer": tag_str(buf, b"COMM"),
            "year": tag_str(buf, b"YEAR"),
            "flag": tag_str(buf, b"FLAG"),
            "subtunes": subtune_count(buf),
            "file": str(p.relative_to(ARCHIVE)),
            "bytes": p.stat().st_size,
        })
    INDEX.write_text(json.dumps(out, indent=0))
    silent = sum(1 for t in out if "a" in t["flag"])
    multi = sum(1 for t in out if t["subtunes"] > 1)
    print(f"{len(files)} files -> {len(out)} tunes indexed in {INDEX}")
    print(f"  {silent} are FLAG ~a (STE DMA — would play SILENCE here)")
    print(f"  {multi} carry more than one subtune")
    return 0


def score(t: dict, q: str) -> float:
    """Best similarity across title, composer and filename.

    Substring hits win outright; otherwise fall back to fuzzy ratio so a
    misremembered spelling ("Terramis" vs "Teramis") still surfaces.
    """
    best = 0.0
    for field in (t["title"], t["composer"], t["file"]):
        f = field.lower()
        if q in f:
            return 1.0 + len(q) / max(len(f), 1)  # prefer the tightest match
        best = max(best, SequenceMatcher(None, q, f).ratio())
    return best


def search(query: str, limit: int) -> int:
    if not INDEX.exists():
        sys.exit(f"no {INDEX} — run: python3 {sys.argv[0]} --build")
    tunes = json.loads(INDEX.read_text())
    q = query.lower()
    ranked = sorted(tunes, key=lambda t: score(t, q), reverse=True)[:limit]
    if not ranked or score(ranked[0], q) < 0.45:
        print(f"nothing close to {query!r}. Try a distinctive word, or a stem "
              f"(the archive's spelling often differs from the title you were given).")
        return 1

    print(f"{'TITLE':<34} {'COMPOSER':<20} {'FLAG':<6} {'SUB':>3}  FILE")
    for t in ranked:
        if score(t, q) < 0.45:
            break
        warn = "  <-- STE DMA: plays SILENCE here" if "a" in t["flag"] else ""
        print(f"{t['title'][:33]:<34} {t['composer'][:19]:<20} "
              f"{t['flag']:<6} {t['subtunes']:>3}  {t['file']}{warn}")
    print("\nVerify before wiring it in:")
    print("  node apps/sndh_headless.mjs prototypes/sndh_lf/<file> [subtune]")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Find a tune in the local SNDH archive by name.")
    ap.add_argument("query", nargs="*", help="title, composer or filename fragment")
    ap.add_argument("--build", action="store_true", help="(re)build the index")
    ap.add_argument("-n", type=int, default=10, help="max results (default 10)")
    a = ap.parse_args()
    if a.build:
        return build()
    if not a.query:
        ap.error("give a search term, or --build")
    return search(" ".join(a.query), a.n)


if __name__ == "__main__":
    sys.exit(main())
