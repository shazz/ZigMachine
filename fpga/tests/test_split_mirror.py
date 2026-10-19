"""The audio-state mirror's place in the system table (1.2): hostAudioMirror is a host entry
APPENDED after 1.1's, so a 1.1 cart keeps every index and runs on a 1.2 system (and is simply not
mirrored), while a 1.2 cart hands the system its ZigOS fields right after its instantiation. The
monolithic env.c makes the same call through host_audio_mirror_bind (host/boot.c)."""

from __future__ import annotations

import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import host_bridges
import host_split
import split_image
import sys_abi
from host_bridges import MIRROR, STREAM
from sys_abi_c import env_rows
from sys_abi_manifest import parse

GETTERS = {n: ("u32", []) for n in host_bridges.MIRROR_FIELDS}


def test_the_mirror_entry_is_appended_to_1_1_as_a_minor_bump() -> None:
    m = parse(sys_abi.MANIFEST.read_text())
    assert m.version >= (1, 2) and (1, 2) in [v for v, _ in m.history]
    rows = env_rows(m)
    assert rows[-1] == ("hostAudioMirror", "host", "void", ["u32", "u32", "u32"])
    assert [n for n, *_ in rows[-1 - len(STREAM) : -1]] == sorted(STREAM), "1.1's indices moved"
    assert split_image.abi_ok(1 << 16 | 1, 1 << 16 | 2) and not split_image.abi_ok(1 << 16 | 2, 1 << 16 | 1)


def test_a_lean_cart_hands_its_fields_to_the_table_entry() -> None:
    glue = host_split.cart_mirror(GETTERS)
    assert "zm_sys->fn[ZM_ENV_hostAudioMirror]" in glue and "zm_sys->count > ZM_ENV_hostAudioMirror" in glue
    assert "w2c_cart_getYmRegsPointer(c), w2c_cart_getAudioModePointer(c), w2c_cart_getSongMsPointer(c)" in glue


def test_a_cart_without_the_getters_hands_zeros() -> None:
    """A C or Rust cart has no ZigOS: nothing to mirror, and no undefined symbol."""
    assert "c_mirror(e, 0u, 0u, 0u)" in host_split.cart_mirror({})
    assert "getSongMsPointer" not in host_split.cart_mirror({"getSongMsPointer": ("u32", ["u32"])})


def test_the_monolithic_env_binds_through_the_same_hook() -> None:
    bind = host_bridges.mirror_bind(GETTERS)
    assert bind.startswith("void host_audio_mirror_bind(struct w2c_env* e)")
    assert "HOST_AUDIO_MIRROR(e, w2c_cart_getYmRegsPointer(&e->cart)" in bind
    assert "#ifndef HOST_AUDIO_MIRROR" in host_bridges.HOST_DEFAULTS, "the native host needs the no-op"


def test_the_system_serves_the_entry_with_its_hook() -> None:
    rows = {n: ("host", r, p) for n, (r, p, _) in {**STREAM, **MIRROR}.items()}
    tail = host_split.system_tail(rows, {})
    assert "[ZM_ENV_hostAudioMirror] = (zm_fn)t_hostAudioMirror," in tail
    fwd = host_split.forwarder("hostAudioMirror", "void", ["u32", "u32", "u32"], None, {})
    assert "HOST_AUDIO_MIRROR(e, a0, a1, a2)" in fwd
