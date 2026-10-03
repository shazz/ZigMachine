"""Break tests for the glass's input path: the mouse and the joypad on the ARM
(fpga/glass/src, `zig build test`) and the cart CPU's pointer dispatch
(glass/firmware/glass_input.c). Each mutant breaks one rule in a copy of the
sources and requires the tests to fail, as tests/test_rtl_glass.py does for
the RTL (whose pointer mutants live there). ZM_RTL_BREAK=1 runs them.

The copies live under fpga/build, never in fpga/glass: the checkout is shared.
"""

import os
import runpy
import shutil
import subprocess
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
GLASS = FPGA / "glass"
WORK = FPGA / "build" / "glass" / "mutants"
ZIG = os.environ.get("ZIG", str(Path.home() / ".local/zig/0.16.0/zig"))

M, A, P, E = "src/mouse.zig", "src/app.zig", "src/pad.zig", "src/evdev.zig"
# (id, file under fpga/glass, text, broken text)
ZIG_MUTANTS = [
    ("mouse_clamp", M, "std.math.clamp(self.fx +| value *| self.scale, 0, MAX_X)", "self.fx +| value *| self.scale"),
    ("mouse_y_rate", M, "@divTrunc(value *| self.scale, 2)", "value *| self.scale"),
    ("mouse_scale", M, "value *| self.scale, 0, MAX_X", "value *| SCALE_ONE, 0, MAX_X"),
    ("mouse_any_button", M, "if (self.held != 0) map.PTR_BTN_PRESS", "if (self.held & 1 != 0) map.PTR_BTN_PRESS"),
    ("mouse_double", M, "self.double = quick;", "self.double = false;"),
    ("mouse_pad_buttons", M, "code <= BTN_MOUSE_LAST", "code <= BTN_MOUSE_LAST + 0x10"),
    ("app_osd_mouse", A, "if (!self.open) self.mouse.update", "self.mouse.update"),
    ("app_osd_release", A, "if (self.mouse.release()) |w| self.regs.write(map.REG_POINTER, w);", ""),
    ("pad_dead_zone", P, "const dead = @divTrunc(r.max - r.min, 6);", "const dead: i32 = 0;"),
    ("pad_mid", P, "const mid = @divTrunc(r.min + r.max, 2);", "const mid: i32 = 0;"),
    ("pad_threshold", P, "v < mid - dead", "v <= mid - dead"),
    ("pad_hat_range", P, "ABS_HAT0X => self.axis(value, .{}", "ABS_HAT0X => self.axis(value, self.x"),
    ("pad_dpad", P, "BTN_DPAD_UP + 2 => self.set(map.JOY_LEFT", "BTN_DPAD_UP + 2 => self.set(map.JOY_RIGHT"),
    ("pad_trigger", P, "BTN_TRIGGER, BTN_SOUTH, BTN_EAST =>", "BTN_SOUTH, BTN_EAST =>"),
    ("evdev_stick", E, "return prop_bits & NOT_A_STICK == 0;", "return true;"),
]

F = "glass_input.c"
C_MUTANTS = [
    ("fw_ptr_once", F, "if (seq == *seen) return -1;", ""),
    ("fw_ptr_no_export", F, "*seen = seq;\n    if (pointer) {", "if (!pointer) return -1;\n    *seen = seq;\n    {"),
    ("fw_ptr_y", F, "(ptr >> PTR_Y_SHIFT)", "(ptr >> PTR_X_SHIFT)"),
]

BREAK = pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")


def _mutate(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    assert text.count(old) == 1, f"the text to break is not unique in {path}"
    path.write_text(text.replace(old, new))


def _glass_copy(name: str) -> Path:
    """fpga/glass's sources and build.zig, its ../../ paths pointed back at the repo."""
    work = WORK / name
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(GLASS / "src", work / "src")
    rel = os.path.relpath(ROOT, work)
    (work / "build.zig").write_text((GLASS / "build.zig").read_text().replace('b.path("../../', f'b.path("{rel}/'))
    return work


@BREAK
@pytest.mark.parametrize(("name", "file", "old", "new"), ZIG_MUTANTS, ids=[m[0] for m in ZIG_MUTANTS])
def test_a_broken_input_rule_is_caught_on_the_arm(name: str, file: str, old: str, new: str) -> None:
    work = _glass_copy(name)
    _mutate(work / file, old, new)
    r = subprocess.run([ZIG, "build", "test"], cwd=work, capture_output=True, text=True, timeout=600, check=False)
    assert r.returncode != 0, f"{name} went unnoticed"
    assert "error:" in r.stderr and "failed" in r.stderr, f"{name}: no test failed, the build did:\n{r.stderr}"


@BREAK
@pytest.mark.parametrize(("name", "file", "old", "new"), C_MUTANTS, ids=[m[0] for m in C_MUTANTS])
def test_a_broken_pointer_rule_is_caught_on_the_cart_cpu(name: str, file: str, old: str, new: str) -> None:
    work = WORK / name
    shutil.rmtree(work, ignore_errors=True)
    shutil.copytree(GLASS / "firmware", work)
    _mutate(work / file, old, new)
    values = runpy.run_path(str(FPGA / "gen" / "glass_map.py"))
    defines = [f"-D{k}={v}u" for k, v in values.items() if k.isupper() and isinstance(v, int)]
    exe = work / "glass_input_test"
    cmd = [
        "clang",
        "-std=c11",
        "-Wall",
        f"-I{work}",
        *defines,
        str(work / F),
        str(FPGA / "tests/tb/glass_input_test.c"),
    ]
    subprocess.run([*cmd, "-o", str(exe)], check=True)
    r = subprocess.run([exe], capture_output=True, text=True, check=False)
    assert r.returncode != 0, f"{name} went unnoticed:\n{r.stdout}"
