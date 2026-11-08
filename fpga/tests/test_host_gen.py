"""The native host's generated half (tools/host_gen.py, tools/wasm_info.py) must
make the same decisions apps/scene_hash.mjs makes. The high-water port is checked
against the JS itself on every module the host runs; the import resolution and the
LinkError refusal are checked on hand-built inputs, including the failing cases.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(FPGA / "tools"))

import host_gen
import wasm_info

MODULES = sorted(ROOT.glob("docs/demo-*.wasm")) + [ROOT / "docs/rom.wasm", ROOT / "docs/machine-video.wasm"]


def _js_high_waters(paths: list[Path]) -> dict[str, int | None]:
    script = (
        "const m = await import(process.argv[1]); const fs = await import('node:fs');"
        "const out = {}; for (const p of process.argv.slice(2)) out[p] = m.cartHighWater(fs.readFileSync(p));"
        "console.log(JSON.stringify(out));"
    )
    hiwater = (ROOT / "docs/wasm_hiwater.js").as_uri()
    cmd = ["node", "--input-type=module", "-e", script, hiwater, *map(str, paths)]
    return json.loads(subprocess.run(cmd, check=True, capture_output=True, text=True).stdout)


@pytest.mark.skipif(shutil.which("node") is None, reason="node runs the JS reference")
def test_high_water_matches_wasm_hiwater_js_on_every_module() -> None:
    expected = _js_high_waters(MODULES)
    got = {str(p): wasm_info.high_water(p.read_bytes()) for p in MODULES}
    assert got == expected


def test_high_water_of_a_module_without_globals_or_data_is_none() -> None:
    assert wasm_info.high_water(b"\0asm\1\0\0\0") is None


def test_high_water_rejects_a_non_wasm_file() -> None:
    with pytest.raises(ValueError, match="not a wasm module"):
        wasm_info.high_water(b"\x7fELF\1\0\0\0")


def test_memory_import_reads_the_shared_112_page_limits() -> None:
    assert wasm_info.memory_import((ROOT / "docs/rom.wasm").read_bytes()) == (112, 112)


def test_link_check_refuses_a_module_whose_max_is_below_the_shared_memory(tmp_path: Path) -> None:
    # (module "env" "memory" (memory 48 48)): the JS host's LinkError case (demo-audio.wasm)
    imp = b"\x01\x03env\x06memory\x02\x01\x30\x30"
    wasm = tmp_path / "small.wasm"
    wasm.write_bytes(b"\0asm\1\0\0\0\x02" + bytes([len(imp)]) + imp)
    with pytest.raises(SystemExit, match="LinkError"):
        host_gen.link_check({"cart": wasm}, 112)


EXPORTS = {"rom": {"guiText": ("void", ["u32"])}, "machine": {"hwBlit": ("void", [])}, "cart": {}}


def test_resolve_prefers_rom_then_the_machine_list_then_a_stub() -> None:
    assert host_gen.resolve("guiText", {"cart"}, EXPORTS) == "rom"
    assert host_gen.resolve("hwBlit", {"cart", "rom"}, EXPORTS) == "machine"
    assert host_gen.resolve("hwClear", {"cart"}, EXPORTS) is None  # not in scene_hash's list
    assert host_gen.resolve("hblDispatch", {"machine"}, EXPORTS) == "cart"


def test_resolve_refuses_a_cart_that_imports_hbldispatch() -> None:
    with pytest.raises(SystemExit, match="hblDispatch"):
        host_gen.resolve("hblDispatch", {"machine", "cart"}, EXPORTS)


def test_stub_returns_what_undefined_converts_to() -> None:
    assert "return 0;" in host_gen.forwarder("hostAudioFeed2", "u32", ["u32", "u32"], None, EXPORTS)
    assert "return NAN;" in host_gen.forwarder("f", "f32", [], None, EXPORTS)
    assert "wasm_rt_trap" in host_gen.forwarder("g", "u64", [], None, EXPORTS)


def test_disk_read_block_is_the_drive_and_its_range_error_traps() -> None:
    drive = host_gen.forwarder("diskReadBlock", "u32", ["u32", "u32"], None, EXPORTS)
    assert "host_disk_read(&host_disk, a0, a1, e->memory.data, e->memory.size)" in drive
    assert "if (n < 0) wasm_rt_trap(WASM_RT_TRAP_OOB);" in drive
    with pytest.raises(SystemExit, match="drive"):
        host_gen.forwarder("diskReadBlock", "void", ["u32", "u32"], None, EXPORTS)


def test_forwarder_refuses_a_signature_mismatch() -> None:
    with pytest.raises(SystemExit, match="does not match"):
        host_gen.forwarder("guiText", "void", ["u32", "u32"], "rom", EXPORTS)


def test_forwarder_wraps_the_hbl_dispatch_and_the_blitter_in_span_hooks() -> None:
    exports = {"machine": {"hwBlit": ("void", [])}, "cart": {"hblDispatch": ("void", ["u32"])}, "rom": {}}
    blit = host_gen.forwarder("hwBlit", "void", [], "machine", exports)
    hbl = host_gen.forwarder("hblDispatch", "void", ["u32"], "cart", exports)
    assert "HOST_SPAN_ENTER(HOST_SPAN_BLIT); w2c_machine_hwBlit(&e->machine); HOST_SPAN_LEAVE();" in blit
    assert "HOST_SPAN_ENTER(HOST_SPAN_CART); w2c_cart_hblDispatch(&e->cart, a0); HOST_CHISEL_SYNC(); HOST_SPAN_LEAVE();" in hbl
    assert "HOST_SPAN" not in host_gen.forwarder("guiText", "void", ["u32"], "rom", EXPORTS)


def test_every_entry_that_can_touch_lazy_memory_waits_for_a_lazy_chisel_op() -> None:
    """cycles/bchisel.h: the ROM may draw with the CPU, the drive may overwrite a lazy op's source,
    the arena's alloc zeroes memory; hwBlit waits inside, after its own setup."""
    exports = {
        "machine": {"hwBlit": ("void", []), "hwRamAlloc": ("u32", ["u32", "u32"])},
        "cart": {},
        "rom": {"guiText": ("void", ["u32"]), "romDepack": ("u32", ["u32", "u32"])},
    }
    rom = host_gen.forwarder("guiText", "void", ["u32"], "rom", exports)
    depack = host_gen.forwarder("romDepack", "u32", ["u32", "u32"], "rom", exports)
    alloc = host_gen.forwarder("hwRamAlloc", "u32", ["u32", "u32"], "machine", exports)
    drive = host_gen.forwarder("diskReadBlock", "u32", ["u32", "u32"], None, exports)
    assert "{ HOST_CHISEL_SYNC(); w2c_rom_guiText(&e->rom, a0); }" in rom
    assert "HOST_CHISEL_SYNC(); return w2c_rom_romDepack(" in depack
    assert "HOST_CHISEL_SYNC(); return w2c_machine_hwRamAlloc(" in alloc
    assert drive.index("HOST_CHISEL_SYNC();") < drive.index("host_disk_read(")
    assert "HOST_CHISEL_SYNC" not in host_gen.forwarder("hwBlit", "void", [], "machine", exports)
    assert "#define HOST_CHISEL_SYNC() ((void)0)" in host_gen.SPAN_HOOKS, "the native host needs the no-op"


def test_a_getter_does_not_wait_for_a_lazy_chisel_op() -> None:
    """A getter returns a value and touches no memory: no check, so the wrapper stays a tail jump."""
    exports = {"machine": {"hwVideoBase": ("u32", [])}, "cart": {}, "rom": {"romScratchPtr": ("u32", [])}}
    mach = host_gen.forwarder("hwVideoBase", "u32", [], "machine", exports)
    rom = host_gen.forwarder("romScratchPtr", "u32", [], "rom", exports)
    assert mach.endswith("{ return w2c_machine_hwVideoBase(&e->machine); }\n")
    assert rom.endswith("{ return w2c_rom_romScratchPtr(&e->rom); }\n")


def test_every_getter_is_a_value_returning_entry_without_side_effects() -> None:
    """The list is the contract: no entry that draws, depacks, allocates or resets may be in it."""
    doers = {"hwBlit", "hwRamAlloc", "hwRamMark", "hwRamRelease", "romDepack", "romReset", "romInstallPalettePlane"}
    for name in host_gen.GETTERS:
        assert name in host_gen.MACHINE_ENV or name.startswith(("rom", "desk")), name
        assert not name.startswith(("gui", "dialog", "fileSel")) and name not in doers, name


def test_forwarder_refuses_a_span_that_returns_a_value() -> None:
    exports = {"machine": {"hwBlit": ("u32", [])}, "cart": {}, "rom": {}}
    with pytest.raises(SystemExit, match="span"):
        host_gen.forwarder("hwBlit", "u32", [], "machine", exports)


def test_host_micros_calls_the_board_hook_whose_default_is_the_stubs_zero() -> None:
    clock = host_gen.forwarder("hostMicros", "u32", [], None, EXPORTS)
    assert clock == "u32 w2c_env_hostMicros(struct w2c_env* e) { (void)e; return HOST_MICROS(); }\n"
    assert "#define HOST_MICROS() 0u" in host_gen.HOOK_DEFAULTS


def test_host_micros_with_the_wrong_signature_is_refused() -> None:
    with pytest.raises(SystemExit):
        host_gen.forwarder("hostMicros", "f32", [], None, EXPORTS)
    with pytest.raises(SystemExit):
        host_gen.forwarder("hostMicros", "u32", ["u32"], None, EXPORTS)


def test_the_stream_imports_call_their_hooks_whose_default_is_the_stubs_no_op() -> None:
    feed = host_gen.forwarder("hostAudioFeed", "void", ["u32", "u32"], None, EXPORTS)
    assert feed == "void w2c_env_hostAudioFeed(struct w2c_env* e, u32 a0, u32 a1) { HOST_AUDIO_FEED(e, a0, a1); }\n"
    start = host_gen.forwarder("hostAudioStreamStart", "void", ["f32"], None, EXPORTS)
    assert "HOST_AUDIO_STREAM_START(e, a0);" in start
    assert "HOST_AUDIO_STREAM_STOP(e);" in host_gen.forwarder("hostAudioStreamStop", "void", [], None, EXPORTS)
    assert "#define HOST_AUDIO_FEED(e, ptr, len) ((void)(e), (void)(ptr), (void)(len))" in host_gen.HOST_DEFAULTS


def test_the_paula_imports_call_their_hooks_and_the_claim_returns_its_answer() -> None:
    claim = host_gen.forwarder("hostPaulaClaim", "u32", ["u32"], None, EXPORTS)
    assert claim == "u32 w2c_env_hostPaulaClaim(struct w2c_env* e, u32 a0) { return HOST_PAULA_CLAIM(e, a0); }\n"
    write = host_gen.forwarder("hostPaulaWrite", "void", ["u32", "u32"], None, EXPORTS)
    assert write == "void w2c_env_hostPaulaWrite(struct w2c_env* e, u32 a0, u32 a1) { HOST_PAULA_WRITE(e, a0, a1); }\n"
    # No Paula where no player runs: the default claim is 0, so the cart mixes in software.
    assert "#define HOST_PAULA_CLAIM(e, lead) ((void)(e), (void)(lead), 0u)" in host_gen.HOST_DEFAULTS


def test_the_mp3_imports_call_their_hooks_and_the_status_defaults_to_no_player() -> None:
    ctl = host_gen.forwarder("hostMp3Ctl", "void", ["u32", "u32"], None, EXPORTS)
    assert ctl == "void w2c_env_hostMp3Ctl(struct w2c_env* e, u32 a0, u32 a1) { HOST_MP3_CTL(e, a0, a1); }\n"
    status = host_gen.forwarder("hostMp3Status", "u32", ["u32"], None, EXPORTS)
    assert status == "u32 w2c_env_hostMp3Status(struct w2c_env* e, u32 a0) { return HOST_MP3_STATUS(e, a0); }\n"
    # Where no player runs (a sim, the plain native host), status 0: the cart says "no MP3 player".
    assert "#define HOST_MP3_STATUS(e, which) ((void)(e), (void)(which), 0u)" in host_gen.HOST_DEFAULTS


def test_an_mp3_import_with_the_wrong_signature_is_refused() -> None:
    with pytest.raises(SystemExit, match="MP3 stream"):
        host_gen.forwarder("hostMp3Feed", "void", ["u32"], None, EXPORTS)


def test_the_bard_queue_attach_calls_its_hook_and_defaults_to_no_queue() -> None:
    attach = host_gen.forwarder("hostBardAttach", "u32", ["u32", "u32"], None, EXPORTS)
    assert attach == "u32 w2c_env_hostBardAttach(struct w2c_env* e, u32 a0, u32 a1) { return HOST_BARD_ATTACH(e, a0, a1); }\n"
    # Where no player runs (a sim, the plain native host), 0: the cart says "no BARD queue here".
    assert "#define HOST_BARD_ATTACH(e, block, lead) ((void)(e), (void)(block), (void)(lead), 0u)" in host_gen.HOST_DEFAULTS


def test_a_bard_attach_with_the_wrong_signature_is_refused() -> None:
    with pytest.raises(SystemExit, match="BARD queue"):
        host_gen.forwarder("hostBardAttach", "u32", ["u32"], None, EXPORTS)


def test_kos_drive_read_calls_its_hook_whose_default_reads_the_c_image() -> None:
    read = host_gen.forwarder("kosDriveRead", "u32", ["u32", "u32", "u32", "u32"], None, EXPORTS)
    assert read == ("u32 w2c_env_kosDriveRead(struct w2c_env* e, u32 a0, u32 a1, u32 a2, u32 a3) "
                    "{ return HOST_KOS_DRIVE_READ(e, a0, a1, a2, a3); }\n")  # fmt: skip
    assert "host_kos_drive_read(&host_cdisk, (unit), (sector), (count), (dst)" in host_gen.HOST_DEFAULTS
    assert "host_disk_t host_cdisk;" in host_gen.DRIVE_DEF
    with pytest.raises(SystemExit, match="C: drive"):
        host_gen.forwarder("kosDriveRead", "u32", ["u32", "u32"], None, EXPORTS)


def test_a_paula_import_with_the_wrong_signature_is_refused() -> None:
    with pytest.raises(SystemExit, match="Paula"):
        host_gen.forwarder("hostPaulaClaim", "void", ["u32"], None, EXPORTS)


def test_a_stream_import_with_the_wrong_signature_is_refused() -> None:
    with pytest.raises(SystemExit, match="stream"):
        host_gen.forwarder("hostAudioFeed", "void", ["u32"], None, EXPORTS)
    with pytest.raises(SystemExit, match="stream"):
        host_gen.forwarder("hostAudioStreamStart", "u32", ["f32"], None, EXPORTS)
