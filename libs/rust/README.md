# `libs/rust/` — Rust helper crate *(placeholder)*

Reserved for a future **Rust helper crate** (`no_std`) over the HW ABI
(`machine/sdk/`): safe wrappers for the framebuffer, palette, HBL and blitter, so
Rust apps get ergonomic drawing instead of raw pointer writes (see
`apps/rust/hello.rs` for the bare-metal baseline).

Nothing here yet. A Rust app today talks to the machine directly with two imports
(`hwVideoBase` + `env.memory`) — see `apps/rust/README.md`.

## Intended build
A `cdylib`/`rlib` compiled for `wasm32-unknown-unknown` and linked into a Rust app
via rustc's bundled `rust-lld`.
