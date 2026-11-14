"""The ITEM SELECTOR's geometry from a LOCAL asset directory's manifest (gem_assets_conv.py).

The manifest lists TOS 4's SELECTOR tree per screen mode (the aes340 picture's objects, in
pixels). This reads where each piece of the selector sits, for the 8-pixel font (st_medium)
and the 16-pixel one (falcon16), as rom/gem/engine/assets_none.zig's `Selector`, which
rom/gem/desktop/fsel_draw.zig uses instead of our own layout (fsel_geom.zig: ours).

LICENCE RULE: the numbers come from Matt's local reconstruction and only ever land in the
generated module in the build cache, never in the source tree. This file holds names, not
coordinates.
"""

from __future__ import annotations

MODES = {"st_medium": 8, "falcon16": 16}
# Geom field -> the object in the SELECTOR tree, by name or (unnamed strings) by text.
NAMED = {
    "dir": "FDIRECTO", "sel": "FSELECTI", "drive_label": "FSDRIVE", "closer": "FCLSBOX", "mask": "FTITLE",
    "list": "FILEBOX", "row": "F1NAME", "scroll": "SCRLBAR", "up": "FUPAROW", "track": "FSVSLID",
    "down": "FDNAROW", "drives": "DRVBOX", "drive": "DRIVEA", "ok": "OK", "cancel": "CANCEL",
}
TEXTS = {"dir_label": "Directory:", "sel_label": "Selection:"}
FIELDS = list(NAMED) + list(TEXTS)


def absolute(objs: list[dict]) -> list[list[int]]:
    """Each object's rect from the box's top left (the manifest's are relative to the parent)."""
    out, stack = [], []
    for o in objs:
        d = o["depth"]
        del stack[d:]
        px, py = (out[stack[-1]][0], out[stack[-1]][1]) if d else (0, 0)
        x, y, w, h = o["rect"]
        out.append([px + x, py + y, w, h] if d else [0, 0, w, h])
        stack.append(len(out) - 1)
    return out


def one(e: dict) -> dict:
    objs = e["objects"]
    rects = absolute(objs)
    by_name = {o["name"]: i for i, o in enumerate(objs) if o.get("name")}
    by_text = {o["text"]: i for i, o in enumerate(objs) if o["type"] == "G_STRING"}
    need = [n for n in list(NAMED.values()) + ["FLABEL", "F2NAME", "DRIVEB", "DRIVEC"] if n not in by_name]
    need += [t for t in TEXTS.values() if t not in by_text]
    if need:
        raise SystemExit(f"gem_assets_fsel: {e['file']}: no {', '.join(need)}")
    sel = {"ch": MODES[e["mode"]], "w": rects[0][2], "h": rects[0][3], "title_y": rects[by_name["FLABEL"]][1]}
    for k, n in NAMED.items():
        sel[k] = list(rects[by_name[n]])
    for k, t in TEXTS.items():
        sel[k] = list(rects[by_text[t]])
    lead = len(objs[by_name["FSDRIVE"]]["text"]) - len(objs[by_name["FSDRIVE"]]["text"].lstrip())
    sel["drive_label"][0] += 8 * lead  # we draw the label without its leading blanks
    sel["drive_label"][2] -= 8 * lead
    sel["pitch"] = rects[by_name["F2NAME"]][1] - rects[by_name["F1NAME"]][1]
    sel["dx"] = rects[by_name["DRIVEB"]][0] - rects[by_name["DRIVEA"]][0]
    sel["dy"] = rects[by_name["DRIVEC"]][1] - rects[by_name["DRIVEA"]][1]
    return sel


def selectors(entries: list[dict]) -> list[dict]:
    """The aes340 SELECTOR geometry per font height, from the manifest's entries."""
    out = {}
    for e in entries:
        if e.get("tree") == "SELECTOR" and "aes340" in e.get("file", "") and e.get("mode") in MODES and e.get("objects"):
            out[MODES[e["mode"]]] = one(e)
    return [out[k] for k in sorted(out)]


def emit(sels: list[dict]) -> str:
    def r4(v):
        return ".{" + ",".join(str(int(x)) for x in v) + "}"

    def sel(s):
        parts = [f".{k} = {s[k]}" for k in ("ch", "w", "h", "title_y", "pitch", "dx", "dy")]
        parts += [f".{k} = {r4(s[k])}" for k in FIELDS]
        return ".{ " + ", ".join(parts) + " }"

    return "pub const selectors: []const Selector = &[_]Selector{" + ",".join(sel(s) for s in sels) + "};"
