"""Top view of the case layout (fpga/case/PLAN.md): parts, panel ports and the extenders' slack loops.
A sketch to agree on before the OpenSCAD model: uv run --with matplotlib python fpga/case/layout_topview.py"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Arc, Rectangle  # noqa: E402

W, FRONT, BACK = 373.0, 157.0, 170.0  # width, keyboard tray depth (the reference's), electronics depth
WALL = 3.0
Y0 = FRONT  # the joint between the tray and the electronics section
OUT = Path(__file__).with_name("layout_topview.png")

# name, x, y, w, h (mm, y = depth from the front edge), colour
PARTS = [
    ("Z-66 keyboard (rests on top)", 6.5, 16, 360, 125, "#d8d8e8"),
    ("Z7-Lite\n(back edge: HDMI\nRJ45 USB-A;\nfront edge:\n2x USB-C,\nSD below)", 112, 215, 60, 80, "#7fbf7f"),
    ("6-port hub\n(cables on 4 sides)", 240, 230, 75, 40, "#7fa8d8"),
    ("iCode\nDB9 x2", 12, 175, 90, 40, "#e0b070"),
]
# label, wall ("back"|"left"|"right"), position along that wall (mm), screw spacing (mm)
PORTS = [
    ("HDMI", "back", 95, 28), ("RJ45", "back", 145, 28), ("FPGA\nUSB-C", "back", 222, 17),
    ("DEBUG\nUSB-C", "back", 260, 17), ("HUB\nUSB-C", "back", 298, 17),
    ("DB9 J0", "left", Y0 + 60, 25), ("DB9 J1", "left", Y0 + 105, 25),
    ("MOUSE", "right", Y0 + 30, 30), ("WI-FI", "right", Y0 + 70, 30),
    ("JACK", "right", Y0 + 105, 0), ("SD", "right", Y0 + 135, 0),
]
# slack loops: label, centre x, centre y, opening ("up"/"down"/"left"/"right")
LOOPS = [("HDMI/RJ45 loop", 70, 270, "right"), ("USB-C x3 loop", 225, 190, "up"),
         ("USB2 x2 (55 cm)", 340, 300, "left"), ("DB9 x2", 60, 250, "right"), ("SD / jack", 330, 185, "left")]


def draw_case(ax: plt.Axes) -> None:
    ax.add_patch(Rectangle((0, 0), W, FRONT + BACK, fill=False, lw=2))
    ax.add_patch(Rectangle((WALL, WALL), W - 2 * WALL, FRONT + BACK - 2 * WALL, fill=False, lw=0.5, ls=":"))
    ax.plot([0, W], [Y0, Y0], color="k", lw=1.2, ls="--")
    ax.text(W / 2, Y0 + 3, "joint: tray | electronics (49 mm wall)", ha="center", fontsize=7)
    ax.plot([W / 2, W / 2], [0, FRONT + BACK], color="grey", lw=0.8, ls="-.")
    ax.text(W / 2 + 2, FRONT + BACK - 8, "print split (left | right)", fontsize=6, color="grey")


def draw_parts(ax: plt.Axes) -> None:
    for name, x, y, w, h, c in PARTS:
        ax.add_patch(Rectangle((x, y), w, h, facecolor=c, edgecolor="k", lw=0.8))
        ax.text(x + w / 2, y + h / 2, name, ha="center", va="center", fontsize=6)


def port_xy(wall: str, pos: float) -> tuple[float, float, float]:
    if wall == "back":
        return pos, FRONT + BACK, 0.0
    return (0.0 if wall == "left" else W), pos, 90.0


def draw_ports(ax: plt.Axes) -> None:
    for label, wall, pos, spacing in PORTS:
        x, y, rot = port_xy(wall, pos)
        size = (spacing or 12) + 8
        if rot:
            ax.add_patch(Rectangle((x - 4, y - size / 2), 8, size, facecolor="#c33", edgecolor="k"))
            ax.text(x + (10 if wall == "left" else -10), y, label, ha="left" if wall == "left" else "right",
                    va="center", fontsize=6)
        else:
            ax.add_patch(Rectangle((x - size / 2, y - 4), size, 8, facecolor="#c33", edgecolor="k"))
            ax.text(x, y - 9, label, ha="center", va="top", fontsize=6)


def draw_loops(ax: plt.Axes) -> None:
    angle = {"up": 0, "left": 90, "down": 180, "right": 270}
    for label, x, y, way in LOOPS:
        ax.add_patch(Arc((x, y), 60, 60, angle=angle[way], theta1=180, theta2=360, color="#906", lw=2))
        ax.text(x, y, label, ha="center", va="center", fontsize=6, color="#906")


def main() -> None:
    fig, ax = plt.subplots(figsize=(12, 10))
    draw_case(ax)
    draw_parts(ax)
    draw_ports(ax)
    draw_loops(ax)
    ax.set_xlim(-30, W + 30)
    ax.set_ylim(-10, FRONT + BACK + 15)
    ax.set_aspect("equal")
    ax.set_title(f"KESTREL case, top view: {W:.0f} x {FRONT + BACK:.0f} mm (tray {FRONT:.0f} + electronics {BACK:.0f}),"
                 " 49 high; loops = 6 cm U bends", fontsize=9)
    ax.set_xlabel("width (mm)")
    ax.set_ylabel("depth from the front edge (mm)")
    fig.savefig(OUT, dpi=110, bbox_inches="tight")
    print(OUT)


if __name__ == "__main__":
    main()
