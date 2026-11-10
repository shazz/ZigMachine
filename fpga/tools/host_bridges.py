"""The cart-facing tables of the native host's env.c (tools/host_gen.py writes them):
the --call export table, and the song, input and disk-app bridges the host and the board
firmware call the cart through (host/host.h host_song_bridge, host_input_bridge,
host_disk_app_bridge)."""

# How a --call argument (a JS Number, as a double) becomes each wasm parameter type.
FROM_NUMBER = {"u32": "host_to_i32(a[{i}])", "f32": "(f32)a[{i}]", "f64": "a[{i}]"}


def export_table(cart: dict[str, tuple[str, list[str]]], inst: str = "&e->cart") -> str:
    """--call wrappers for every cart export whose parameters a JS Number can feed; `inst` is the
    cart instance (the lean cart image keeps its own pointer, tools/host_split.py)."""
    out, rows = [], []
    for name, (_, params) in sorted(cart.items()):
        if any(t not in FROM_NUMBER for t in params):
            continue
        args = "".join(", " + FROM_NUMBER[t].format(i=i) for i, t in enumerate(params))
        out.append(
            f"static void x_{name}(struct w2c_env* e, const double* a) {{ (void)a; w2c_cart_{name}({inst}{args}); }}"
        )
        rows.append(f'    {{"{name.replace("__", "_")}", x_{name}}},')
    return "\n".join(out) + "\n\nconst host_export host_exports[] = {\n" + "\n".join(rows) + "\n    {0, 0},\n};\n"


# The song bridge (host.h host_song_bridge), in its field order, with the signature each must have.
SONG_BRIDGE = [("pollSongRequest", []), ("songNamePtr", []), ("songNameLen", []), ("songTune", []),
               ("pollSndhCalls", []), ("sndhCallD0", ["u32"]), ("sndhCallNamePtr", []), ("sndhCallNameLen", []),
               ("pollSfx", []), ("sfxEntriesPtr", [])]  # fmt: skip


# The input bridge (host.h host_input_bridge), in its field order, with the signature each must have.
INPUT_BRIDGE = [("ownsKeyboard", "u32", []), ("input", "void", ["u32"]), ("inputRelease", "void", ["u32"]),
                ("key", "void", ["u32"]), ("keyUp", "void", ["u32"]), ("setShadeMode", "u32", ["u32"]),
                ("pointer", "void", ["u32", "u32", "u32"])]  # fmt: skip


# The disk-app bridge (host.h host_disk_app_bridge), in its field order, with the signature each must have.
DISK_APP_BRIDGE = [("insertDisk", "void", ["u32"]), ("isBooted", "u32", []), ("diskDirPtr", "u32", []),
                   ("setDiskFileCount", "void", ["u32"]), ("pollCartRequest", "u32", []),
                   ("getCartTagPtr", "u32", []), ("getCartTagLen", "u32", [])]  # fmt: skip


def disk_app_bridge(cart: dict[str, tuple[str, list[str]]]) -> str:
    """host_dapp: each disk export the cart has (with the expected type), else NULL."""
    rows = [f"w2c_cart_{n}" if cart.get(n) == (r, p) else "0" for n, r, p in DISK_APP_BRIDGE]
    return "const host_disk_app_bridge host_dapp = {" + ", ".join(rows) + "};\n"


def input_bridge(cart: dict[str, tuple[str, list[str]]]) -> str:
    """host_input: each input export the cart has (with the expected type), else NULL."""
    rows = [f"w2c_cart_{n}" if cart.get(n) == (r, p) else "0" for n, r, p in INPUT_BRIDGE]
    return "const host_input_bridge host_input = {" + ", ".join(rows) + "};\n"


def song_bridge(cart: dict[str, tuple[str, list[str]]]) -> str:
    """host_songs: each export the cart has (with the expected type), else NULL."""
    rows = [f"w2c_cart_{n}" if cart.get(n) == ("u32", p) else "0" for n, p in SONG_BRIDGE]
    return "const host_song_bridge host_songs = {" + ", ".join(rows) + "};\n"


# The stream ring's imports (zg.audioStreamStart / audioFeed / audioStreamStop): a hook macro each,
# a no-op by default as the JS stub; a host with the players (-include host/hstream.h: the board
# firmware, host_audio) defines them to reach the ring as the browser's loader does.
STREAM = {
    "hostAudioStreamStart": ("void", ["f32"], "HOST_AUDIO_STREAM_START"),
    "hostAudioFeed": ("void", ["u32", "u32"], "HOST_AUDIO_FEED"),
    "hostAudioStreamStop": ("void", [], "HOST_AUDIO_STREAM_STOP"),
}
STREAM_DEFAULTS = """/* Stream hooks: the stub's no-op. host/hstream.h (-include) defines them where the players run. */
#ifndef HOST_AUDIO_STREAM_START
#define HOST_AUDIO_STREAM_START(e, rate) ((void)(e), (void)(rate))
#define HOST_AUDIO_FEED(e, ptr, len) ((void)(e), (void)(ptr), (void)(len))
#define HOST_AUDIO_STREAM_STOP(e) ((void)(e))
#endif
"""


# A cart's Paula (HW 1.14.0, apps/zig/demo_audio_paula.zig): claim, chip RAM upload, timed register
# writes, release. Hooks as the stream's: the claim answers 0 (no Paula for the cart: it mixes in
# software) unless host/hstream.h (-include, where the players run) defines them.
PAULA = {
    "hostPaulaClaim": ("u32", ["u32"], "HOST_PAULA_CLAIM"),
    "hostPaulaUpload": ("void", ["u32", "u32", "u32"], "HOST_PAULA_UPLOAD"),
    "hostPaulaWrite": ("void", ["u32", "u32"], "HOST_PAULA_WRITE"),
    "hostPaulaRelease": ("void", [], "HOST_PAULA_RELEASE"),
}
PAULA_DEFAULTS = """/* Paula hooks: no Paula for the cart (claim 0). host/hstream.h (-include) defines them where the players run. */
#ifndef HOST_PAULA_CLAIM
#define HOST_PAULA_CLAIM(e, lead) ((void)(e), (void)(lead), 0u)
#define HOST_PAULA_UPLOAD(e, src, off, len) ((void)(e), (void)(src), (void)(off), (void)(len))
#define HOST_PAULA_WRITE(e, ptr, n) ((void)(e), (void)(ptr), (void)(n))
#define HOST_PAULA_RELEASE(e) ((void)(e))
#endif
"""


# KOS's C: (docs/KOS_FAT.md F5): kosDriveRead(unit, sector, count, dst) reads `count` 512-byte
# sectors of drive `unit` (2: C:, the SD card) into the cart's memory at `dst` and answers how many
# it read, 0 for none (no such drive, a sector past the end, a dst outside memory, a timeout). A
# cart import (only KOS's desktop shell has it), served by the system: the default reads the image
# in host_cdisk (host/disk.h: the native host's --c-image, empty elsewhere); the board firmware's
# cycles/bkosdrive.h (-include) asks glass for the sectors over the window's request block.
KOS_DRIVE = {"kosDriveRead": ("u32", ["u32", "u32", "u32", "u32"], "HOST_KOS_DRIVE_READ")}
KOS_DRIVE_DEFAULTS = """/* C: (KOS F5): host_cdisk's image unless cycles/bkosdrive.h (-include, the board) defines it. */
#ifndef HOST_KOS_DRIVE_READ
#define HOST_KOS_DRIVE_READ(e, unit, sector, count, dst) \\
    host_kos_drive_read(&host_cdisk, (unit), (sector), (count), (dst), (e)->memory.data, (e)->memory.size)
#endif
"""

# C:'s writes (docs/KOS_GEMDOS.md §7, rom/kos/kfs_abi.zig): kosFileOp(req) hands the host a whole-file
# request the cart wrote at `req` (12 words: op, flags, slot, attr, offset, len, data, path, path_len,
# path2, path2_len, gen) and answers a TOS code. A system-table entry since 1.10. The default calls
# host_kos_file_hook (host/disk.h): the native host sets it to KFS over host_cdisk (host/kos_cfile.c);
# unset (a sim, a test), C:'s writes answer EDRIVE. The board firmware's cycles/bkosfile.h (-include)
# asks glass, which writes the card through Linux's FAT (glass/src/kos_file.zig).
KOS_FILE = {"kosFileOp": ("u32", ["u32"], "HOST_KOS_FILE_OP")}
KOS_FILE_DEFAULTS = """/* C:'s writes (KOS GEMDOS phase 2): host_kos_file_hook unless cycles/bkosfile.h (-include, the board) defines it. */
#ifndef HOST_KOS_FILE_OP
#define HOST_KOS_FILE_OP(e, req) \\
    (host_kos_file_hook ? host_kos_file_hook((e)->memory.data, (e)->memory.size, (req)) : (uint32_t)-46)
#endif
"""

# The audio-state mirror (cycles/aud_state.h): the cart's ZigOS fields docs/sealed-loader.js
# writes from the worklet's "audioState" (ym_regs, audio_mode, song_ms), as offsets in its memory,
# handed to the HOST_AUDIO_MIRROR hook once, after the cart's instantiation. No wasm imports it:
# the monolithic env.c calls the hook itself (host_audio_mirror_bind, from host/boot.c), the lean
# cart calls the system table's host entry (tools/host_split.py, table 1.2), which runs the hook.
MIRROR_FIELDS = ["getYmRegsPointer", "getAudioModePointer", "getSongMsPointer"]
MIRROR = {"hostAudioMirror": ("void", ["u32", "u32", "u32"], "HOST_AUDIO_MIRROR")}
MIRROR_DEFAULTS = """/* The audio-state hook: a no-op unless cycles/bmirror.h (-include, the board firmware) defines it. */
#ifndef HOST_AUDIO_MIRROR
#define HOST_AUDIO_MIRROR(e, ym, mode, ms) ((void)(e), (void)(ym), (void)(mode), (void)(ms))
#endif
"""
# The system table's host entries (table 1.1: the stream ring; 1.2: the mirror; 1.6: the cart's
# Paula; 1.8: KOS's C:; 1.10: C:'s writes), and their defaults.
# The MP3 stream (zg.mp3Ctl / mp3Feed / mp3Status, libs/zig/players/mp3.zig, table 1.11): a control,
# a feed of the file's bytes, a status word. Hooks as the stream's: a no-op, and status 0 ("no MP3
# player": the cart says so), unless host/hstream.h (-include, where the players run) defines them.
MP3 = {
    "hostMp3Ctl": ("void", ["u32", "u32"], "HOST_MP3_CTL"),
    "hostMp3Feed": ("void", ["u32", "u32"], "HOST_MP3_FEED"),
    "hostMp3Status": ("u32", ["u32"], "HOST_MP3_STATUS"),
}
MP3_DEFAULTS = """/* MP3 hooks: no player (status 0). host/hstream.h (-include) defines them where the players run. */
#ifndef HOST_MP3_CTL
#define HOST_MP3_CTL(e, op, arg) ((void)(e), (void)(op), (void)(arg))
#define HOST_MP3_FEED(e, ptr, len) ((void)(e), (void)(ptr), (void)(len))
#define HOST_MP3_STATUS(e, which) ((void)(e), (void)(which), 0u)
#endif
"""

# The BARD queue (zg.bard, libs/zig/bard.zig, table 1.12): the cart hands its ring over once; then
# the host drains it each frame with no call. The hook answers 0 ("no BARD queue here": every command
# is refused) unless host/hstream.h (-include, where the players run) defines it.
BARD = {"hostBardAttach": ("u32", ["u32", "u32"], "HOST_BARD_ATTACH")}
BARD_DEFAULTS = """/* The BARD queue's hook: none here (0). host/hstream.h (-include) defines it where the players run. */
#ifndef HOST_BARD_ATTACH
#define HOST_BARD_ATTACH(e, block, lead) ((void)(e), (void)(block), (void)(lead), 0u)
#endif
"""

# The pointer's box (Matt, 9 Nov; glass/src/map_cart.zig VBOX_*, table 1.21): the cart says where its
# picture is, in pointer() coordinates (the SDL layer: kestrel_sdl2/src/kestrel_ptrbox.c), so the board's
# pointer stops there. A no-op unless cycles/bptrhost.h (-include, the board) defines it.
POINTER_BOX = {"hostPointerBox": ("void", ["u32", "u32", "u32", "u32"], "HOST_POINTER_BOX")}
POINTER_BOX_DEFAULTS = """/* The pointer's box: a no-op unless cycles/bptrhost.h (-include, the board firmware) defines it. */
#ifndef HOST_POINTER_BOX
#define HOST_POINTER_BOX(e, x0, y0, x1, y1) ((void)(e), (void)(x0), (void)(y0), (void)(x1), (void)(y1))
#endif
"""

# ZIGNIC, the network card (docs/GEM_NET.md, machine/sdk/net_abi.zig, table 1.22): netOp(req) hands the host a
# 16-word socket request in the cart's memory and answers at once (>= 0 a value, < 0 an Err). Until glass
# serves it on the board (N2: cycles/bnet.h, -include), every host answers no_card (-1).
NET = {"netOp": ("u32", ["u32"], "HOST_NET_OP")}
NET_DEFAULTS = """/* ZIGNIC: no network card (Err.no_card) unless cycles/bnet.h (-include, the board) defines it. */
#ifndef HOST_NET_OP
#define HOST_NET_OP(e, req) ((void)(e), (void)(req), (uint32_t)-1)
#endif
"""

HOST_ENTRIES = {**STREAM, **MIRROR, **PAULA, **KOS_DRIVE, **KOS_FILE, **MP3, **BARD, **POINTER_BOX, **NET}
HOST_DEFAULTS = (STREAM_DEFAULTS + MIRROR_DEFAULTS + PAULA_DEFAULTS + KOS_DRIVE_DEFAULTS + KOS_FILE_DEFAULTS + MP3_DEFAULTS
                 + BARD_DEFAULTS + POINTER_BOX_DEFAULTS + NET_DEFAULTS)


def mirror_args(cart: dict[str, tuple[str, list[str]]], inst: str) -> str:
    """The three offsets: each the cart's getter if it has one (with the expected type), else 0."""
    return ", ".join(f"w2c_cart_{n}({inst})" if cart.get(n) == ("u32", []) else "0u" for n in MIRROR_FIELDS)


def mirror_bind(cart: dict[str, tuple[str, list[str]]]) -> str:
    """host_audio_mirror_bind for the monolithic env.c (host/host.h)."""
    return (f"void host_audio_mirror_bind(struct w2c_env* e) {{ (void)e; "
            f"HOST_AUDIO_MIRROR(e, {mirror_args(cart, '&e->cart')}); }}\n")  # fmt: skip
