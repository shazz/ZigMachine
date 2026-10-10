"""tools/edid_decode.py: the EDID the edid-test bitstream puts on screen, decoded."""

from pathlib import Path

import pytest

from tools.edid_decode import EdidError, decode, parse_text, report

SAMPLE = Path(__file__).resolve().parent / "data" / "edid_hdmi_audio.hex"


def _sample() -> bytes:
    return parse_text(SAMPLE.read_text())


def _screen_rows(data: bytes) -> str:
    """The bytes as the screen shows them: "AA: B0  B1 ... B7  =SS"."""
    rows = []
    for a in range(0, len(data), 8):
        row = data[a : a + 8]
        rows.append(f"{a:02X}: " + "  ".join(f"{v:02X}" for v in row) + f"  ={sum(row) % 256:02X}")
    return "\n".join(rows)


def test_decode_hdmi_monitor_reports_name_hdmi_and_lpcm_audio() -> None:
    info = decode(_sample())
    assert (info.name, info.manufacturer, info.product) == ("ZM TEST HDMI", "ZMC", 0x1234)
    assert (info.hdmi, info.hdmi_address, info.basic_audio) == (True, "1.0.0.0", True)
    assert [(a.name, a.channels, a.rates_khz, a.bits) for a in info.audio] == [
        ("L-PCM", 2, [32, 44.1, 48], [16, 20, 24])
    ]
    assert report(info, 2)[-1] == "48 kHz stereo L-PCM over HDMI: should play"


def test_parse_screen_rows_round_trips_with_row_sums() -> None:
    assert parse_text(_screen_rows(_sample())) == _sample()


def test_parse_screen_row_with_a_misread_byte_names_the_row() -> None:
    text = _screen_rows(_sample()).splitlines()
    assert text[2].startswith("10: 01  24")
    text[2] = text[2].replace("10: 01", "10: 07")  # one byte misread in the row at 0x10
    with pytest.raises(EdidError, match="line 3: row sum"):
        parse_text("\n".join(text))


def test_decode_with_a_bad_block_checksum_is_rejected() -> None:
    data = bytearray(_sample())
    data[200] ^= 0x01
    with pytest.raises(EdidError, match="block 1: checksum"):
        decode(bytes(data))


def test_decode_without_the_edid_header_is_rejected() -> None:
    with pytest.raises(EdidError, match="header"):
        decode(bytes(128))


def test_decode_a_short_read_is_rejected() -> None:
    with pytest.raises(EdidError, match="whole 128-byte blocks"):
        decode(_sample()[:200])


def test_decode_dvi_monitor_without_extension_reports_no_hdmi_no_audio() -> None:
    base = bytearray(_sample()[:128])
    base[126] = 0
    base[127] = (base[127] + 1) % 256  # the checksum follows the extension count
    info = decode(bytes(base))
    assert (info.hdmi, info.basic_audio, info.audio) == (False, False, [])
    assert report(info, 1)[-1] == "48 kHz stereo L-PCM over HDMI: NOT advertised"
