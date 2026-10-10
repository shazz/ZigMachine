"""Decode an EDID read by the edid-test bitstream (rtl/board/edid_test_top.v),
transcribed from its screen, or any EDID file (e.g. /sys/class/drm/*/edid).

    uv run python tools/edid_decode.py edid.txt      # the screen, typed or OCR'd
    uv run python tools/edid_decode.py /sys/class/drm/card1-HDMI-A-1/edid

Text input is the screen's rows, "AA: B0  B1 ... B7  =SS": the "AA:" address and
the "=SS" row sum are optional, and every row sum present is checked, so a
misread byte is pinned to its row. Reports the monitor's name, whether it is an
HDMI sink (a CEA-861 Vendor-Specific Data Block with the IEEE OUI 00-0C-03),
and what audio it takes (the CEA "basic audio" bit, the Audio Data Block).
"""

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

HEADER = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
HDMI_OUI = 0x000C03
AUDIO_FORMATS = {1: "L-PCM", 2: "AC-3", 6: "AAC", 7: "DTS", 10: "E-AC-3", 11: "DTS-HD", 12: "MAT"}
RATES_KHZ = (32, 44.1, 48, 88.2, 96, 176.4, 192)


class EdidError(ValueError):
    """The input is not a valid EDID (or was misread)."""


@dataclass
class AudioFormat:
    name: str
    channels: int
    rates_khz: list[float]
    bits: list[int] = field(default_factory=list)


@dataclass
class EdidInfo:
    manufacturer: str
    product: int
    name: str | None
    extensions: int
    hdmi: bool = False
    hdmi_address: str | None = None
    basic_audio: bool = False
    audio: list[AudioFormat] = field(default_factory=list)


def parse_text(text: str) -> bytes:
    """Bytes from the screen's rows (or any hex dump); checks each "=SS" row sum."""
    out = bytearray()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        m = re.match(r"^([0-9A-Fa-f]{1,4})\s*:\s*(.*)$", line)
        body = m.group(2) if m else line
        body, _, want = body.partition("=")
        row = bytes(int(t, 16) for t in body.split())
        if want.strip() and sum(row) % 256 != int(want, 16):
            raise EdidError(f"line {n}: row sum {sum(row) % 256:02X} != ={want.strip()} (a byte was misread)")
        out += row
    return bytes(out)


def check(data: bytes) -> None:
    if len(data) < 128 or len(data) % 128:
        raise EdidError(f"{len(data)} bytes: an EDID is whole 128-byte blocks")
    if data[:8] != HEADER:
        raise EdidError("block 0 does not start with the EDID header 00 FF FF FF FF FF FF 00")
    for i in range(len(data) // 128):
        total = sum(data[i * 128 : (i + 1) * 128]) % 256
        if total:
            raise EdidError(f"block {i}: checksum fails (bytes sum to {total:02X})")


def _manufacturer(data: bytes) -> str:
    v = data[8] << 8 | data[9]
    return "".join(chr(ord("A") - 1 + (v >> s & 31)) for s in (10, 5, 0))


def _name(block: bytes) -> str | None:
    for off in (54, 72, 90, 108):
        d = block[off : off + 18]
        if d[0] == 0 and d[1] == 0 and d[3] == 0xFC:
            return d[5:18].split(b"\n", 1)[0].decode("ascii", "replace").strip()
    return None


def _sad(sad: bytes) -> AudioFormat:
    fmt = sad[0] >> 3 & 15
    rates = [r for i, r in enumerate(RATES_KHZ) if sad[1] >> i & 1]
    bits = [b for i, b in enumerate((16, 20, 24)) if sad[2] >> i & 1] if fmt == 1 else []
    return AudioFormat(AUDIO_FORMATS.get(fmt, f"format {fmt}"), (sad[0] & 7) + 1, rates, bits)


def _data_blocks(cea: bytes) -> list[tuple[int, bytes]]:
    end, i, blocks = cea[2], 4, []
    while i < end:
        tag, n = cea[i] >> 5, cea[i] & 31
        blocks.append((tag, cea[i + 1 : i + 1 + n]))
        i += 1 + n
    return blocks


def _cea(info: EdidInfo, cea: bytes) -> None:
    info.basic_audio = info.basic_audio or bool(cea[1] >= 2 and cea[3] & 0x40)
    for tag, body in _data_blocks(cea):
        if tag == 1:
            info.audio += [_sad(body[i : i + 3]) for i in range(0, len(body) - 2, 3)]
        elif tag == 3 and len(body) >= 5 and int.from_bytes(body[:3], "little") == HDMI_OUI:
            info.hdmi = True
            info.hdmi_address = f"{body[3] >> 4}.{body[3] & 15}.{body[4] >> 4}.{body[4] & 15}"


def decode(data: bytes) -> EdidInfo:
    check(data)
    info = EdidInfo(_manufacturer(data), data[10] | data[11] << 8, _name(data[:128]), data[126])
    for i in range(1, len(data) // 128):
        if data[i * 128] == 0x02:
            _cea(info, data[i * 128 : (i + 1) * 128])
    return info


def report(info: EdidInfo, blocks: int) -> list[str]:
    lines = [
        f"monitor:    {info.name or '(no name descriptor)'}  [{info.manufacturer} {info.product:04X}]",
        f"HDMI:       {'yes, physical address ' + str(info.hdmi_address) if info.hdmi else 'no (DVI only)'}",
        f"audio:      {'yes' if info.basic_audio or info.audio else 'no'} (basic audio bit {int(info.basic_audio)})",
    ]
    for a in info.audio:
        bits = f", {'/'.join(map(str, a.bits))} bit" if a.bits else ""
        lines.append(f"  {a.name}: {a.channels} ch, {'/'.join(f'{r:g}' for r in a.rates_khz)} kHz{bits}")
    ok = info.hdmi and (info.basic_audio or any(a.name == "L-PCM" and 48 in a.rates_khz for a in info.audio))
    lines.append(f"48 kHz stereo L-PCM over HDMI: {'should play' if ok else 'NOT advertised'}")
    if info.extensions + 1 > blocks:
        lines.append(f"note: {info.extensions} extension(s) announced, {blocks - 1} read (only the first is read)")
    return lines


def load(path: str) -> bytes:
    raw = sys.stdin.buffer.read() if path == "-" else Path(path).read_bytes()
    return raw if raw[:8] == HEADER else parse_text(raw.decode("ascii", "replace"))


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        data = load(argv[0])
        print("\n".join(report(decode(data), len(data) // 128)))
    except (EdidError, ValueError, OSError) as e:
        print(f"edid_decode: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
