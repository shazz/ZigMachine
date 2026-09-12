#!/usr/bin/env python3
"""Understanding a CODEF screen's source: extraction, probing, orientation notes.

The fetching half lives in tools/fetch_codef.py; this half never touches the
network, so it can be exercised against a saved page.html on its own.
"""
from __future__ import annotations

import re
from urllib.parse import urljoin

ASSET_EXT = "png|jpg|jpeg|gif|bmp|ym|mod|sndh|snd|wav|mp3|json|bin|dat|txt"

# What a canvas size tells you about the machine the screen is imitating. CODEF
# authors at the TARGET machine's resolution doubled, so the size identifies the
# original: guessing one ratio for every screen is how a port ends up stretched.
GEOMETRY = [
    (640, 400, "Atari ST 320x200, doubled. Halve every coordinate."),
    (640, 480, "ST 320x240 doubled. The extra 40 rows may be remake slack OR a real "
               "bottom-border screen — screen 198 filled all 240 rows. MEASURE the content."),
    (720, 568, "Amiga PAL overscan, doubled — about 360x284, but screen 525 measured 360x283 "
               "because its doubling grid is offset a row. Not an ST: decide what to crop."),
    (640, 512, "Amiga PAL 320x256, doubled. 56 rows taller than the ST — decide what to crop."),
    (640, 256, "Amiga NTSC-ish 320x128, doubled."),
]


def inline_scripts(html: str) -> str:
    """Every inline <script> body, in order, each under a marker comment.

    The screen's code is usually the longest block, but the audio wiring and the
    asset list can sit in their own blocks, so keep all of them rather than
    guessing which one matters.
    """
    out = []
    for i, body in enumerate(re.findall(r"<script\b[^>]*>(.*?)</script>", html, re.S | re.I)):
        if body.strip():
            out.append(f"// ---- inline block {i} ----\n{body.strip()}\n")
    return "\n".join(out)


def basepath_of(js: str, sid: str) -> tuple[str, bool]:
    """The screen's asset prefix, and whether it was actually declared."""
    m = re.search(r"basepath\s*=\s*[\"']([^\"']+)[\"']", js)
    return (m.group(1), True) if m else (f"screens/{sid}/", False)


def find_assets(js: str, page_url: str, basepath: str) -> list[str]:
    """Absolute URLs for every asset the source names.

    Resolution order matters: a bare 'logo.png' belongs to the screen's own
    basepath ("screens/515/"), while an explicit "screens/028/x.png" is already
    page-relative and must NOT be re-prefixed.
    """
    urls, seen = [], set()
    for name in re.findall(rf"[\"']([A-Za-z0-9_./-]+\.(?:{ASSET_EXT}))[\"']", js, re.I):
        rel = name if "/" in name else basepath + name
        url = urljoin(page_url, rel)
        if url not in seen:
            seen.add(url)
            urls.append(url)
    return urls


def _canvases(js: str) -> list[dict]:
    """Every `new canvas(w, h)`, INCLUDING ones sized by an expression.

    Matching only literal digits made `new canvas(screen_width * 2, h)` invisible,
    and notes.md then reported "No new canvas found" — which sends a porter off
    with no geometry at all. Non-numeric arguments are kept verbatim so the note
    can say "read the source" instead of saying nothing.
    """
    out = []
    for args in re.findall(r"new\s+canvas\s*\(([^)]*)\)", js):
        parts = [a.strip() for a in args.split(",")]
        if len(parts) < 2:
            continue
        w, h = parts[0], parts[1]
        if w.isdigit() and h.isdigit():
            out.append({"w": int(w), "h": int(h)})
        else:
            out.append({"w": w, "h": h, "expr": True})
    return out


def probe(js: str) -> dict:
    """The handful of facts a porter wants before reading 250 lines of JS."""
    return {
        "canvases": _canvases(js),
        "tiles": [
            {"w": int(m[0]), "h": int(m[1]), "first_char": int(m[2]) if m[2] else None}
            for m in re.findall(r"initTile\s*\(\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*(\d+))?", js)
        ],
        "music": sorted(set(re.findall(
            r"[\"']([A-Za-z0-9_. -]+\.(?:sndh|ym|mod|snd|wav|mp3))[\"']", js, re.I))),
        "codef_features": sorted(set(re.findall(
            r"new\s+(scrolltext\w*|canvas|image|music|sprite|rotozoom|tunnel|bump|"
            r"plasma|fire|starfield|vectorial\w*|d3\w*)\b", js))),
    }


def geometry_note(canvases: list[dict]) -> str:
    """Name the machine behind the biggest canvas, rather than assuming the ST."""
    if not canvases:
        return "No `new canvas(...)` found — read the source for the real geometry."
    numeric = [c for c in canvases if not c.get("expr")]
    if not numeric:
        return ("Every canvas is sized by an EXPRESSION, not a literal — read the "
                "source for the real geometry. (Sizes: "
                + "; ".join(f'{c["w"]} x {c["h"]}' for c in canvases) + ")")
    big = max(numeric, key=lambda c: c["w"] * c["h"])
    for w, h, meaning in GEOMETRY:
        if big["w"] == w and big["h"] == h:
            return f"Largest canvas `{w}x{h}`: {meaning}"
    return (f"Largest canvas `{big['w']}x{big['h']}` matches no known target. Work out the "
            f"intended machine before porting — do NOT assume 2x of 320x200.")


def notes(sid: str, mf: dict) -> str:
    """The orientation file a porter (human or agent) reads before the JS."""
    canvases = "\n".join(
        f"- `{c['w']}x{c['h']}`" + ("  (expression — read the source)" if c.get("expr") else "")
        for c in mf["canvases"]) or "- (none found)"
    tiles = "\n".join(
        f"- `{t['w']}x{t['h']}`" + (f", first char {t['first_char']}" if t["first_char"] is not None else "")
        for t in mf["tiles"]) or "- (none found)"
    missing = "".join(f"\n- MISSING (404): `{m}`" for m in mf["missing"])
    return f"""# CODEF screen {sid} — fetched reference

Source: {mf['page']}

Read `screen.js` first, then look up any CODEF call you do not recognise in
`lib/` — `drawTile`, `initTile`, `setmidhandle` and the scrolltext classes all
have real definitions there. Do not infer what they do from their names.

## Geometry (a HINT — measure before you trust it)
{geometry_note(mf['canvases'])}

This is inferred from the canvas size alone. MEASURE where the content actually
sits before deciding: a "640x480" screen turned out to be an ST with the bottom
border open (content filled all 240 rows), and a "720x568" Amiga screen turned
out to be 360x283, not 284, because its doubling grid is offset by a row.

All canvases:
{canvases}

The port target is `zg.WIDTH` x `zg.HEIGHT` = 320x200, or the 400x280 overscan
plane if the screen genuinely uses the borders.

## Tile sets
{tiles}

## Music
{", ".join(mf["music"]) or "(none named in the source — it may load via a player backend)"}

Backends present: {", ".join(l for l in mf["libs"] if "backend" in l or "player" in l) or "(none)"}
(`backend_sc68` = Atari SNDH/SC68; `backend_uade` = Amiga UADE. The backend tells
you which machine the screen came from when the canvas size is ambiguous.)

Put the tune in `docs/music/` and request it with `zg.requestSong("<file>")`, or
`zg.requestSongTune("<file>", n)` for a specific subtune. Check an SNDH's `FLAG`
first: `~a` means STE DMA samples, which the player does not emulate — it loads
and plays SILENCE.

## CODEF features used
{", ".join(mf["codef_features"]) or "(none detected)"}

## Assets
{chr(10).join(f"- `assets/{a}`" for a in mf["assets"]) or "- (none)"}{missing}

Convert with:
`python3 tools/convert_png.py -i assets/<x>.png -r <x>.raw -p <x>_pal.dat`
into `apps/zig/assets/screens/<scene>/`.
"""
