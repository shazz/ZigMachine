"""Aurora boot baker: settings, the lab's colour presets and the timeline (aurora_lab.html `beats()`).

Everything the lab tunes comes from tools/boot/aurora_settings.json; the colour preset is looked up
by name in PRESETS (the JSON only names it). An unknown preset or a missing key is an error: no
fallback values, a silent default would bake a different sky.
"""
import json
from dataclasses import dataclass
from pathlib import Path

W, H = 320, 200
FPS = 30  # the baked rate; the cart runs at 60 Hz and shows each baked frame twice (stars: interpolated)

# aurora_lab.html PRESETS, copied exactly
PRESETS = {
    "Classic green": dict(c0=(0.95, 0.35, 0.75), c1=(0.25, 1.0, 0.55), c2=(0.55, 0.15, 0.45), s0=0.10, s1=0.85),
    "Red-top storm": dict(c0=(0.9, 0.3, 0.8), c1=(0.3, 1.0, 0.5), c2=(1.0, 0.18, 0.2), s0=0.12, s1=0.6),
    "Magenta fringe": dict(c0=(1.0, 0.2, 0.85), c1=(0.3, 0.95, 0.6), c2=(0.35, 0.2, 0.6), s0=0.22, s1=0.9),
    "Teal and violet": dict(c0=(0.6, 0.3, 1.0), c1=(0.2, 0.9, 0.85), c2=(0.5, 0.2, 0.9), s0=0.15, s1=0.75),
}

REQUIRED = ("preset curtains dist foldAmp foldFreq foldSpeed thick base height edge decay rayDen rayCon raySpd "
            "gain bloom exposure pitch yaw fov steps starGain starMin starThr photoDim horizon starsAlone dur "
            "flyAt morphLen hold swirl fadeIn fadeOut wingHz wingAmp bird").split()


class SettingsError(ValueError):
    pass


def load_settings(path):
    """The settings dict with its preset's colours merged in; SettingsError when anything is missing."""
    try:
        s = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise SettingsError(f"cannot read settings {path}: {e}") from e
    missing = [k for k in REQUIRED if k not in s]
    if missing:
        raise SettingsError(f"settings lack {missing}")
    if s["preset"] not in PRESETS:
        raise SettingsError(f"unknown preset {s['preset']!r}")
    if s["bird"] not in ("KESTREL", "PEREGRINE"):
        raise SettingsError(f"unknown bird {s['bird']!r}")
    return {**s, **PRESETS[s["preset"]]}


@dataclass(frozen=True)
class Beats:
    a0: float
    a1: float
    m0: float
    m1: float
    e1: float
    w0: float
    end: float
    total: float


def beats(p):
    a0 = p["starsAlone"]
    a1 = a0 + p["dur"]
    m0 = max(0.2, p["flyAt"])
    m1 = m0 + p["morphLen"]
    e1 = m1 + 0.7
    end = max(e1 + p["hold"], a1)
    return Beats(a0, a1, m0, m1, e1, e1, end, end + 0.6)


def smooth(x):
    return x * x * (3 - 2 * x)
