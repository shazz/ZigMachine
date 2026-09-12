# `libs/c/` — C convenience library *(placeholder)*

Reserved for a future **C-ABI shim** over the HW ABI (`machine/sdk/`): palette,
text, HBL-registration and blitter helpers so C apps get conveniences instead of
poking the raw memory map (see `apps/c/hello.c` for the bare-metal baseline).

Nothing here yet. A C app today talks to the machine directly with two imports
(`hwVideoBase` + `env.memory`) — see `apps/c/README.md`.

## Intended build
Header + source compiled alongside a C app with `zig cc` (bundled lld); the shim
would ship as a `.h` linked per app, not a separate wasm artifact.
