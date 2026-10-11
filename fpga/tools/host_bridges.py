"""The cart-facing tables of the native host's env.c (tools/host_gen.py writes them):
the --call export table, and the song and input bridges the host and the board
firmware call the cart through (host/host.h host_song_bridge, host_input_bridge)."""

# How a --call argument (a JS Number, as a double) becomes each wasm parameter type.
FROM_NUMBER = {"u32": "host_to_i32(a[{i}])", "f32": "(f32)a[{i}]", "f64": "a[{i}]"}


def export_table(cart: dict[str, tuple[str, list[str]]]) -> str:
    """--call wrappers for every cart export whose parameters a JS Number can feed."""
    out, rows = [], []
    for name, (_, params) in sorted(cart.items()):
        if any(t not in FROM_NUMBER for t in params):
            continue
        args = "".join(", " + FROM_NUMBER[t].format(i=i) for i, t in enumerate(params))
        out.append(
            f"static void x_{name}(struct w2c_env* e, const double* a) {{ (void)a; w2c_cart_{name}(&e->cart{args}); }}"
        )
        rows.append(f'    {{"{name.replace("__", "_")}", x_{name}}},')
    return "\n".join(out) + "\n\nconst host_export host_exports[] = {\n" + "\n".join(rows) + "\n    {0, 0},\n};\n"


# The song bridge (host.h host_song_bridge), in its field order, with the signature each must have.
SONG_BRIDGE = [("pollSongRequest", []), ("songNamePtr", []), ("songNameLen", []), ("songTune", []),
               ("pollSndhCalls", []), ("sndhCallD0", ["u32"]), ("sndhCallNamePtr", []), ("sndhCallNameLen", []),
               ("pollSfx", []), ("sfxEntriesPtr", [])]


# The input bridge (host.h host_input_bridge), in its field order, with the signature each must have.
INPUT_BRIDGE = [("ownsKeyboard", "u32", []), ("input", "void", ["u32"]), ("inputRelease", "void", ["u32"]),
                ("key", "void", ["u32"]), ("keyUp", "void", ["u32"]), ("setShadeMode", "u32", ["u32"]),
                ("pointer", "void", ["u32", "u32", "u32"])]


def input_bridge(cart: dict[str, tuple[str, list[str]]]) -> str:
    """host_input: each input export the cart has (with the expected type), else NULL."""
    rows = [f"w2c_cart_{n}" if cart.get(n) == (r, p) else "0" for n, r, p in INPUT_BRIDGE]
    return "const host_input_bridge host_input = {" + ", ".join(rows) + "};\n"


def song_bridge(cart: dict[str, tuple[str, list[str]]]) -> str:
    """host_songs: each export the cart has (with the expected type), else NULL."""
    rows = [f"w2c_cart_{n}" if cart.get(n) == ("u32", p) else "0" for n, p in SONG_BRIDGE]
    return "const host_song_bridge host_songs = {" + ", ".join(rows) + "};\n"
