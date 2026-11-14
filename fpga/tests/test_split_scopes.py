"""The scopes' place in the system table (1.26, tools/host_scopes.py): hostAudioScopes is a host entry
APPENDED, so 1.2's hostAudioMirror row and every 1.25 index stand (a 1.25 cart runs, its scopes flat on
the board), while a 1.26 cart hands the system its zigos.scopes right after its instantiation, beside the
mirror's fields. The monolithic env.c makes the same call through host_audio_mirror_bind."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
# A clean tree has no gen/ (the gate's fresh worktree): the memmap split_image imports, made first.
if not (FPGA / "gen" / "glass_cart.py").exists():
    subprocess.run(["make", "-s", "-C", str(FPGA), "memmap"], check=True, capture_output=True)
import host_bridges  # noqa: E402  (after gen/ exists)
import host_split  # noqa: E402
import split_image  # noqa: E402
import sys_abi  # noqa: E402
from host_scopes import SCOPES
from sys_abi_c import env_rows
from sys_abi_manifest import parse

GETTERS = {n: ("u32", []) for n in [*host_bridges.MIRROR_FIELDS, "getScopesPointer"]}


def test_the_scopes_entry_is_appended_as_a_minor_bump() -> None:
    m = parse(sys_abi.MANIFEST.read_text())
    assert m.version >= (1, 26) and (1, 25) in [v for v, _ in m.history]
    names = [n for n, *_ in env_rows(m)]
    assert ("hostAudioScopes", "host", "void", ["u32"]) in env_rows(m)
    assert names.index("hostAudioScopes") > names.index("hostBardJob"), "1.25's indices moved"
    assert split_image.abi_ok(1 << 16 | 25, 1 << 16 | 26) and not split_image.abi_ok(1 << 16 | 26, 1 << 16 | 25)


def test_a_lean_cart_hands_its_scopes_to_the_table_entry() -> None:
    glue = host_split.cart_mirror(GETTERS)
    assert "zm_sys->fn[ZM_ENV_hostAudioScopes]" in glue and "zm_sys->count > ZM_ENV_hostAudioScopes" in glue
    assert "c_scopes(e, w2c_cart_getScopesPointer(c))" in glue
    assert "c_mirror(e, w2c_cart_getYmRegsPointer(c), w2c_cart_getAudioModePointer(c), w2c_cart_getSongMsPointer(c))" in glue


def test_a_cart_without_scopes_hands_zero() -> None:
    """A C or Rust cart, or a getter of another type: nothing to write, and no undefined symbol."""
    assert "c_scopes(e, 0u)" in host_split.cart_mirror({})
    assert "getScopesPointer" not in host_split.cart_mirror({"getScopesPointer": ("u32", ["u32"])})


def test_the_monolithic_env_binds_the_scopes_through_the_same_hook() -> None:
    bind = host_bridges.mirror_bind(GETTERS)
    assert "HOST_AUDIO_SCOPES(e, w2c_cart_getScopesPointer(&e->cart))" in bind
    assert "#ifndef HOST_AUDIO_SCOPES" in host_bridges.HOST_DEFAULTS, "the native host needs the no-op"


def test_the_system_serves_the_entry_with_its_hook() -> None:
    rows = {n: ("host", r, p) for n, (r, p, _) in SCOPES.items()}
    assert "[ZM_ENV_hostAudioScopes] = (zm_fn)t_hostAudioScopes," in host_split.system_tail(rows, {})
    assert "HOST_AUDIO_SCOPES(e, a0)" in host_split.forwarder("hostAudioScopes", "void", ["u32"], None, {})
