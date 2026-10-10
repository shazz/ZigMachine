"""The audio RTL (rtl/audio/, rtl/board/ym_test_*, docs/FPGA_AUDIO.md) against the
Zig machine. tests/audio_ref/audio_ref.zig runs machine/audio (engine.zig,
ym.zig) on a stimulus script; the CXXRTL testbenches play the same script or
dump into the RTL and compare:
  - the PCM path, sample for sample (it must be exact);
  - the YM, as music (jt49 and ym.zig are different models: spectra, partials);
  - the ym-test bitstream end to end through HDMI at 44.1 kHz.
Break tests (ZM_RTL_BREAK=1) break one rule at a time and require a failure.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yowasp_yosys

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tests"))
import test_rtl  # after the path insert: reuses its compile step
from audio_scripts import ac_rms, left, write_pcm_script, write_pokey_script, write_ym_script

BUILD = FPGA / "build" / "tests" / "audio"
ZIG = os.environ.get("ZIG", str(Path.home() / ".local/zig/0.16.0/zig"))
TUNE = FPGA.parent / "docs/music/union/Drooling.ymraw"
JT49 = [f"third_party/jt49/hdl/jt49{m}.v" for m in ("", "_cen", "_div", "_eg", "_exp", "_noise")]
POKEY = [f"rtl/audio/zm_pokey{m}.v" for m in ("", "_pair", "_poly")]
CORE = [f"rtl/audio/zm_audio_{m}.v" for m in ("frac", "ym", "pokey", "pcm", "mix", "core")] + POKEY + JT49
YM_AUDIO = [*CORE, "rtl/board/zm_dump_player.v", "rtl/board/ym_test_audio.v"]
HDMI = ["rtl/board/hdmi_pattern.v", "rtl/video/zm_vtiming.v", "rtl/video/zm_tmds_enc.v", *test_rtl.HDMI_SRCS]
SOC = [*CORE, "rtl/audio/zm_audio_sched.v", "rtl/audio/zm_audio_soc.v", "rtl/video/zm_video_sdpram.v"]
YM_CORE = [*YM_AUDIO, "rtl/audio/zm_audio_fifo.v", "rtl/board/snd_lab_out.v", "rtl/board/ym_test_core.v", *HDMI]
FAST = "-chparam SR_MOD 40000 -chparam YM_MOD 2"  # a 4 MHz system clock: same fractions, 12x fewer clocks
SECONDS = 3

LOOP = (120, 40)  # the loop test's ROM: Drooling's first 120 frames, looping back to frame 40

# (name, top, sources, testbench, -chparam ..., the dump ROM it plays)
BENCHES = {
    "core": ("zm_audio_core", CORE, "tests/tb/audio_core_tb.cpp", "", "tune"),
    "core_fast": ("zm_audio_core", CORE, "tests/tb/audio_core_tb.cpp", FAST, "tune"),
    "core100": ("zm_audio_core", CORE, "tests/tb/audio_core_tb.cpp", "-chparam SR_MOD 1000000 -chparam YM_MOD 50", "tune"),
    "ym_audio": ("ym_test_audio", YM_AUDIO, "tests/tb/ym_audio_tb.cpp", FAST + " -chparam WORDS {words}", "tune"),
    "ym_loop": ("ym_test_audio", YM_AUDIO, "tests/tb/ym_audio_tb.cpp", FAST + " -chparam WORDS {words}", "loop"),
    "ym_core": ("ym_test_core", YM_CORE, "tests/tb/ym_test_tb.cpp", "-chparam WORDS {words}", "tune"),
    # the board SoC's core: stamped writes through zm_audio_sched (453 clocks a sample: room for a burst)
    "soc": ("zm_audio_soc", SOC, "tests/tb/audio_soc_tb.cpp", "-chparam SR_MOD 200000 -chparam YM_MOD 10", "tune"),
}


def _run(cmd: list[str], cwd: Path = BUILD) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=600, check=False)


def build_bench(name: str, root: Path = FPGA, out: Path = BUILD) -> Path:
    """The testbench `name` over the sources under `root`, built in `out`."""
    top, sources, tb, chparam, rom = BENCHES[name]
    out.mkdir(parents=True, exist_ok=True)
    cc = out / f"{name}.cc"
    reads = " ".join(str(root / s) for s in sources)
    defs = f'-I{FPGA / "gen"} -DYM_ROM="{BUILD / rom}.hex"'
    hier = chparam.format(words=sum(1 for _ in (BUILD / f"{rom}.hex").open()))
    script = f"read_verilog -defer {defs} {reads}; hierarchy -top {top} {hier}; proc; write_cxxrtl {cc}"
    assert yowasp_yosys.run_yosys(["-q", "-p", script]) == 0, f"yosys failed on {name}"
    (out / f"{top}.cc").write_text(cc.read_text())  # the name the testbench includes
    exe = out / f"{name}_tb"
    inc = [f"-I{test_rtl.CXXRTL_INCLUDE}", f"-I{out}"]
    subprocess.run(["clang++", "-std=c++17", "-O2", *inc, str(FPGA / tb), "-o", str(exe)], check=True)
    return exe


@pytest.fixture(scope="module", autouse=True)
def oracle() -> None:
    """The Zig harness, the tune's ROM, and the stimulus scripts."""
    BUILD.mkdir(parents=True, exist_ok=True)
    root, eng = FPGA / "tests/audio_ref/audio_ref.zig", FPGA.parent / "machine/audio/engine.zig"
    pk = FPGA.parent / "machine/audio/pokey.zig"
    cmd = [ZIG, "build-exe", "-OReleaseSafe", "--dep", "engine", "--dep", "pokey", f"-Mroot={root}", f"-Mengine={eng}",
           f"-Mpokey={pk}"]
    subprocess.run([*cmd, f"-femit-bin={BUILD / 'audio_ref'}"], check=True, cwd=BUILD)
    rom = [sys.executable, str(FPGA / "tools/ym_rom.py"), str(TUNE), str(BUILD / "tune.hex")]
    subprocess.run([*rom, "--bin", str(BUILD / "tune.bin")], check=True, capture_output=True)
    excerpt = [str(BUILD / "loop.hex"), "--bin", str(BUILD / "loop.bin"), "--frames", str(LOOP[0])]
    subprocess.run([*rom[:3], *excerpt, "--loop", str(LOOP[1])], check=True, capture_output=True)
    write_pcm_script(BUILD)
    write_ym_script(BUILD)
    write_pokey_script(BUILD)
    frames = SECONDS * 50
    (BUILD / "tune.txt").write_text(f"rom tune.bin {frames}\n")
    (BUILD / "tune_ym.txt").write_text(f"ymraw {TUNE} {frames}\n")
    (BUILD / "loop.txt").write_text(f"rom loop.bin {LOOP[0] * 2 - LOOP[1]}\n")  # through the loop, twice
    for s in ("pcm", "ym", "ym_hold", "tune", "tune_ym", "loop", "pokey"):
        r = _run([str(BUILD / "audio_ref"), f"{s}.txt", f"{s}.zig.raw"])
        assert r.returncode == 0, r.stderr


def test_the_rom_plays_as_the_ym_file_in_the_machine() -> None:
    assert (BUILD / "tune.zig.raw").read_bytes() == (BUILD / "tune_ym.zig.raw").read_bytes()


@pytest.mark.parametrize(
    ("bench", "args"),
    [
        ("core", ["pcm.txt", "pcm.zig.raw", "exact"]),
        ("core_fast", ["ym.txt", "ym.zig.raw", "ym"]),
        ("ym_audio", ["tune.zig.raw"]),
        ("ym_loop", ["loop.zig.raw"]),
        ("ym_core", []),
        ("soc", ["pcm.txt", "pcm.zig.raw"]),
        ("core100", ["pokey.txt", "pokey.zig.raw", "exact"]),
    ],
    ids=["pcm_exact", "ym_script", "ym_dump", "ym_dump_loop", "ym_test_hdmi", "soc_stamped_exact", "pokey_exact"],
)
def test_rtl_audio(bench: str, args: list[str]) -> None:
    r = _run([str(build_bench(bench)), *args])
    print(r.stdout)
    assert r.returncode == 0, r.stdout + r.stderr


def test_the_envelope_holds_as_the_datasheet_says() -> None:
    """YM2149 datasheet: shape 11 (CONT ALT HOLD, decay) ends held at the TOP,
    shape 15 (CONT ATT ALT HOLD, attack) ends held at ZERO: the hold takes the
    alternated level. jt49 does; machine/audio/ym.zig holds both at the end of
    the ramp (11 at zero, 15 at the top), which the Zig side shows here. So
    channel A (a tone gated by the envelope) keeps sounding after shape 11 and is
    silent after shape 15, on the RTL."""
    r = _run([str(build_bench("core_fast")), "ym_hold.txt", "ym_hold.zig.raw", "dump", "ym_hold.rtl.raw"])
    assert r.returncode == 0, r.stdout
    rtl, zig = left(BUILD / "ym_hold.rtl.raw"), left(BUILD / "ym_hold.zig.raw")
    (r11, z11), (r15, z15) = ([ac_rms(s[a + 2205 : a + 4410]) for s in (rtl, zig)] for a in (0, 4410))
    print(f"tone A after the ramp: shape 11 rtl {r11:.0f} zig {z11:.0f}; shape 15 rtl {r15:.0f} zig {z15:.0f}")
    assert r11 > 4000 and r15 < 50


# (id, bench, file, text, broken text, the testbench's arguments)
MUTANTS = [
    ("pcm_gain_sign", "core", "rtl/audio/zm_audio_pcm.v", "11'sd128 - pan_c, m_r0", "11'sd128 + pan_c, m_r0"),
    (
        "pcm_min_gain",
        "core",
        "rtl/audio/zm_audio_pcm.v",
        "(m_l0 > 11'sd128) ? 11'sd128",
        "(m_l0 > 11'sd255) ? 11'sd255",
    ),
    ("pcm_loop_end", "core", "rtl/audio/zm_audio_pcm.v", "{1'b0, p} >= loop_end", "{1'b0, p} > loop_end"),
    ("pcm_no_stop", "core", "rtl/audio/zm_audio_pcm.v", "if (mix_stop) active[c] <= 1'b0;", ""),
    ("pcm_loop_one", "core", "rtl/audio/zm_audio_pcm.v", "ll[c] > 24'd1", "ll[c] > 24'd0"),
    ("pcm_step_late", "core", "rtl/audio/zm_audio_pcm.v", "pos[c] <= p + {8'd0, step[c]}", "pos[c] <= p"),
    ("pcm_trig_pos", "core", "rtl/audio/zm_audio_pcm.v", "pos[wch] <= 40'd0;", ""),
    ("pcm_dirty", "core", "rtl/audio/zm_audio_pcm.v", "if (busy) dirty <= dirty | {hit_act, hit_pos};", ""),
    ("pcm_dirty_all", "core", "rtl/audio/zm_audio_pcm.v", "!dirty[0] && !hit_pos", "dirty == 2'b00 && !hit_pos"),
    ("mix_clamp", "core", "rtl/audio/zm_audio_mix.v", "16'h7FFF : c[23:8]", "16'h7FFE : c[23:8]"),
    ("mix_floor", "core", "rtl/audio/zm_audio_mix.v", "to16(pcm_l + ym + pk)", "to16(pcm_l + ym + pk + 29'sd128)"),
    ("reset_mixer", "core", "rtl/audio/zm_audio_core.v", "8'h3F : 8'h00", "8'h00 : 8'h00"),
    ("ym_clock", "ym_audio", "rtl/audio/zm_audio_ym.v", ".sel(1'b1)", ".sel(1'b0)"),
    ("ym_frame", "ym_audio", "rtl/board/ym_test_audio.v", "FRAME = 882;", "FRAME = 441;"),
    ("ym_r13_ff", "core_fast", "rtl/audio/zm_audio_core.v", "&& wdata[7:0] == 8'hFF", "&& 1'b0"),
    ("ym_no_box", "ym_audio", "rtl/audio/zm_audio_ym.v", "{acc, n} <= 0;", "{acc, n} <= {acc, n};"),
    ("player_jump", "ym_loop", "rtl/board/zm_dump_player.v", "JWAIT: st <= JUMP;", "JWAIT: st <= READ;"),
    ("player_wait", "ym_audio", "rtl/board/zm_dump_player.v", "word[14:0] - 15'd1", "word[14:0]"),
    ("fifo_order", "ym_core", "rtl/audio/zm_audio_fifo.v", "mem[rbin[AW - 1:0]]", "mem[wbin[AW - 1:0]]"),
    ("fifo_no_start", "ym_core", "rtl/audio/zm_audio_fifo.v", "rreq && started && !empty", "rreq && !empty"),
    ("sched_early", "soc", "rtl/audio/zm_audio_sched.v", "ahead == 22'd0 || ahead[21]", "ahead <= 22'd1 || ahead[21]"),
    ("sched_in_mix", "soc", "rtl/audio/zm_audio_sched.v", "due && !mixing && core_ready", "due && core_ready"),
    ("sched_drop", "soc", "rtl/audio/zm_audio_sched.v", "take = push && !full;", "take = push && !full && push_d != 200;"),
    # The POKEY in the core (zm_audio_pokey): the machine's cycles a sample, in step, then the mix.
    ("pk_cycles", "core100", "rtl/audio/zm_audio_pokey.v", "left <= more ? 6'd41 : 6'd40;", "left <= 6'd40;"),
    ("pk_clock_restart", "core100", "rtl/audio/zm_audio_pokey.v", "frac <= 28'd0;", "frac <= frac;"),
    ("pk_mix_stage", "core100", "rtl/audio/zm_audio_pokey.v", "taken <= ran;", "taken <= cen;"),
    ("pk_no_wait", "core100", "rtl/audio/zm_audio_core.v", "(pcm_done || pcm_ready) && !pk_busy", "pcm_done"),
    ("pk_unmixed", "core100", "rtl/audio/zm_audio_mix.v", "pk_p <= pk_sum * kp;", "pk_p <= 32'd0;"),
    ("pk_no_silence", "core100", "rtl/audio/zm_audio_pokey.v", "if (silence) quiet <= 3'd4;", "if (silence) quiet <= 3'd0;"),
    ("pk_kp", "core100", "rtl/audio/zm_audio_mix.v", "6'd41: kp = 20'd872961;", "6'd41: kp = 20'd872960;"),
]
ARGS = {
    "core": ["pcm.txt", "pcm.zig.raw", "exact"],
    "core_fast": ["ym.txt", "ym.zig.raw", "ym"],
    "ym_audio": ["tune.zig.raw"],
    "ym_loop": ["loop.zig.raw"],
    "ym_core": [],
    "soc": ["pcm.txt", "pcm.zig.raw"],
    "core100": ["pokey.txt", "pokey.zig.raw", "exact"],
}


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "bench", "file", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_audio_rule_is_caught(name: str, bench: str, file: str, old: str, new: str) -> None:
    work = BUILD / "mutants" / name
    shutil.rmtree(work, ignore_errors=True)
    for src in BENCHES[bench][1]:
        (work / src).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(FPGA / src, work / src)
    text = (work / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (work / file).write_text(text.replace(old, new))
    r = _run([str(build_bench(bench, work, work)), *ARGS[bench]])
    assert r.returncode != 0, f"{name} went unnoticed:\n{r.stdout}"
