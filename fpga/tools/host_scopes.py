"""The scopes' host entry (system table 1.26, decisions.md 2026-11-14): the cart's zigos.scopes
(its getScopesPointer export), handed to the HOST_AUDIO_SCOPES hook once after its instantiation,
as tools/host_bridges.py's MIRROR fields are. A separate entry appended to the table, so 1.2's
hostAudioMirror row stands and a 1.25 cart still runs (its scopes stay flat on the board).
cycles/bmirror.h defines the hook on the board: BARD then writes the scopes into the cart."""

SCOPES_FIELD = "getScopesPointer"
SCOPES = {"hostAudioScopes": ("void", ["u32"], "HOST_AUDIO_SCOPES")}
SCOPES_DEFAULTS = """/* The scopes' hook: a no-op unless cycles/bmirror.h (-include, the board firmware) defines it. */
#ifndef HOST_AUDIO_SCOPES
#define HOST_AUDIO_SCOPES(e, at) ((void)(e), (void)(at))
#endif
"""


def scopes_arg(cart: dict[str, tuple[str, list[str]]], inst: str) -> str:
    """The scopes' offset: the cart's getter if it has one (with the expected type), else 0."""
    return f"w2c_cart_{SCOPES_FIELD}({inst})" if cart.get(SCOPES_FIELD) == ("u32", []) else "0u"
