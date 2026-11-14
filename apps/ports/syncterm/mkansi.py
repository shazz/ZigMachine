"""Writes data/BBS.ANS, the fake BBS's welcome screen (kestrel_fakebbs.c sends it): our own CP437 ANSI art,
80 columns by 20 rows (SyncTERM keeps the 25th row for its status bar; the fake BBS writes two more lines),
for SyncTERM's ANSI-BBS emulation. Made here, not ripped: a double-line frame, the title in block letters with
a shaded gradient, shade bands and a menu.

    uv run python apps/ports/syncterm/mkansi.py      # -> apps/ports/syncterm/data/BBS.ANS
"""

from __future__ import annotations

from pathlib import Path

ESC = "\x1b["
OUT = Path(__file__).resolve().parent / "data" / "BBS.ANS"

# A 5x5 block font for the title (one bit a pixel, high bit left); each pixel is two cells wide.
FONT: dict[str, list[int]] = {
    "Z": [0b11111, 0b00010, 0b00100, 0b01000, 0b11111],
    "I": [0b11111, 0b00100, 0b00100, 0b00100, 0b11111],
    "G": [0b01111, 0b10000, 0b10011, 0b10001, 0b01111],
    "B": [0b11110, 0b10001, 0b11110, 0b10001, 0b11110],
    "S": [0b01111, 0b10000, 0b01110, 0b00001, 0b11110],
    " ": [0, 0, 0, 0, 0],
}
# The title's colours, one a row: bright blue down to cyan (ANSI SGR foreground, 1 = bold/bright).
ROW_SGR = ["1;34", "1;34", "1;36", "0;36", "1;37"]


def sgr(code: str) -> str:
    return f"{ESC}{code}m"


def at(row: int, col: int) -> str:
    return f"{ESC}{row};{col}H"


def frame() -> str:
    """The double-line box around the screen: rows 1..20, columns 1..80."""
    top = "\xc9" + "\xcd" * 78 + "\xbb"
    bottom = "\xc8" + "\xcd" * 78 + "\xbc"
    s = sgr("0;1;34;40") + at(1, 1) + top
    for r in range(2, 20):
        s += at(r, 1) + "\xba" + at(r, 80) + "\xba"
    return s + at(20, 1) + bottom


def title(text: str, row: int) -> str:
    width = sum(4 if ch == " " else 12 for ch in text) - 2
    col0 = (80 - width) // 2 + 1
    s = ""
    for y in range(5):
        s += at(row + y, col0) + sgr(ROW_SGR[y])
        for ch in text:
            if ch == " ":
                s += "    "
                continue
            bits = FONT[ch][y]
            for x in range(5):
                s += "\xdb\xdb" if bits & (0x10 >> x) else "  "
            s += "  "
    return s


def shade_band(row: int) -> str:
    """A full-width band from dark to light and back: the four CP437 shade characters."""
    ramp = "\xb0\xb1\xb2\xdb\xb2\xb1\xb0"
    colours = ["0;34", "0;36", "1;36", "1;37", "1;36", "0;36", "0;34"]
    s = at(row, 2)
    for i in range(78):
        k = (i * len(ramp)) // 78
        s += sgr(colours[k]) + ramp[k]
    return s


def centred(row: int, text: str, code: str) -> str:
    return at(row, (80 - len(text)) // 2 + 1) + sgr(code) + text


def menu(row: int) -> str:
    items = [("M", "Message bases"), ("F", "File areas"), ("D", "Door games"), ("G", "Goodbye")]
    s = ""
    for i, (key, name) in enumerate(items):
        s += at(row + i, 26) + sgr("1;37") + "[" + sgr("1;33") + key + sgr("1;37") + "] " + sgr("0;37") + name
        s += at(row + i, 46) + sgr("0;34") + "\xfa" * 8
    return s


def screen() -> bytes:
    s = sgr("0") + f"{ESC}2J" + frame()
    s += title("ZIG BBS", 2)
    s += shade_band(8)
    s += centred(10, "Node 1 of 1  \xb3  KESTREL / ZIGGY at 100 MHz  \xb3  SyncTERM in the desk mode", "0;37")
    s += centred(11, "This BBS lives inside the cart: the network is mocked (no TCP/IP yet).", "0;36")
    s += menu(13)
    s += centred(18, "\xfe Telnet negotiated with IAC WILL/DO; the line below says what it learnt \xfe", "0;35")
    s += shade_band(19)
    return (s + sgr("0") + at(21, 1)).encode("latin-1")


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(screen())
    print(f"mkansi: {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
