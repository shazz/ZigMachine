"""soc/board_soc.py + soc.zigmachine_soc --release: each board's release SoC from one table (R41 B2)."""

from __future__ import annotations

import dataclasses

import pytest

from soc import board_soc, boards
from soc.board_soc import BoardSocError, SocParams
from soc.zigmachine_soc import parse_args

# KESTREL v1.3's flags as fpga/boards/microphase_z7_7010/board.mk held them before B2 (BOARD_SOC_FLAGS).
OLD_FLAGS = (
    "--blit --sound-cpu --posted 8 --no-read-bypass --ziggy-reads prefetch "
    "--cpu-netlist {cpu} --sound-core {snd} --vivado-directives fit_timing"
)
KEYS = ("cpu_netlist", "sound_core", "blit", "sound_cpu", "posted", "no_read_bypass", "ziggy_reads",
        "sys_mhz", "comp_mhz", "vivado_directives")  # fmt: skip


def _ns(argv: list[str]) -> dict[str, object]:
    return {k: getattr(parse_args(argv), k) for k in KEYS}


def test_release_gives_kestrel_exactly_the_flags_its_board_mk_used_to_pass() -> None:
    soc = boards.get("kestrel").soc
    old = OLD_FLAGS.format(cpu=soc.cpu_netlist, snd=soc.sound_netlist).split()

    assert _ns(["--target", "z7", "--board", "kestrel", "--release"]) == _ns(["--target", "z7", *old])


def test_without_release_the_parser_defaults_are_unchanged() -> None:
    args = parse_args(["--target", "z7", "--board", "kestrel"])
    assert (args.blit, args.sound_cpu, args.cpu_netlist, args.sound_core) == (False, False, None, None)
    assert (args.no_read_bypass, args.vivado_directives) == (False, "default")


def test_an_explicit_flag_still_wins_over_the_release_default() -> None:
    args = parse_args(["--target", "z7", "--board", "peregrine", "--release", "--posted", "4"])
    assert args.posted == 4 and args.blit


def test_peregrine_starts_with_kestrels_soc() -> None:
    assert boards.get("peregrine").soc == boards.get("kestrel").soc == board_soc.KESTREL_V13


def test_the_netlists_live_in_build_vexgen() -> None:
    soc = board_soc.KESTREL_V13
    assert soc.cpu_netlist == board_soc.FPGA / "build/vexgen/VexRiscv_I16w2D16w2SealFpuZmxE.v"
    assert soc.parser_defaults()["sound_core"] == str(board_soc.FPGA / "build/vexgen/VexRiscv_SndNdD16Dyn8Sx.v")


@pytest.mark.parametrize(
    ("field", "value", "match"),
    [("ziggy_reads", "turbo", "ziggy_reads 'turbo'"), ("vivado_directives", "magic", "vivado_directives"),
     ("posted", -1, "posted -1"), ("sys_mhz", 0.0, "sys 0.0 MHz")],
)  # fmt: skip
def test_an_impossible_parameter_is_refused_at_definition(field: str, value: object, match: str) -> None:
    with pytest.raises(BoardSocError, match=match):
        dataclasses.replace(board_soc.KESTREL_V13, **{field: value})  # type: ignore[arg-type]  # the bad value is the test


def test_make_names_the_same_netlists_as_the_table() -> None:
    """board.mk keeps the two netlists as make prerequisites of `make bitstream`."""
    for b in boards.BOARDS.values():
        mk = (boards.FPGA / "boards" / b.directory / "board.mk").read_text()
        assert f"BOARD_CPU_CORE := build/vexgen/{b.soc.cpu_core}\n" in mk, b.name
        assert f"BOARD_SOUND_CORE := build/vexgen/{b.soc.sound_core}\n" in mk, b.name
        assert "BOARD_SOC_FLAGS" not in mk, b.name


def test_soc_params_has_a_default_for_everything_but_the_two_cores() -> None:
    soc = SocParams("a.v", "b.v")
    assert (soc.blit, soc.posted, soc.read_bypass, soc.ziggy_reads) == (True, 8, False, "prefetch")
