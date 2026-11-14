# SyncTERM on the ZigMachine / KESTREL (the spike)

[SyncTERM](https://www.syncterm.net) (Stephen "Deuce" Hurd and the Synchronet developers) is a BBS terminal in C:
ANSI-BBS, Atari ST VT52, ATASCII, PETSCII, RIP, telnet / rlogin / SSH, X/Y/ZMODEM. This is a SPIKE (Matt, 9 Nov
2026: "do a spike for syncterm to try to compile it even if the ip stack is mocked up"): it compiles, runs in the
desk mode (640x480: the 80x25 screen of 8x16 cells at 1:1, a status line under it), and talks to a BBS that lives
inside the cart, because the machine has no network yet (ZIGNIC, `docs/GEM_NET.md` on `feat/board-wifi`). The
cart is `docs/demo-syncterm.wasm`, a GEM program on `docs/demo-syncterm.zmd`; what the spike found, stubbed and
still needs is `prototypes/syncterm/SPIKE.md`.

## Licence: GPL version 2

SyncTERM is free software under the GNU General Public License version 2 or later (`COPYING`, upstream's
`src/syncterm/gpl.txt`; `src/syncterm/LICENCE`). The cart `docs/demo-syncterm.wasm` is a work based on it and is
distributed under the same licence. Its **corresponding source** is:

- upstream Synchronet at tag `syncterm-1.9`, commit `5bd319427e4f58cd965b056c69bb96ed47db7a81`
  (<https://gitlab.synchro.net/main/sbbs>), unmodified, of which `../fetch.sh` checks out the directories used;
- exactly the patches in `patches/` (`ciolib.c.sed`, `syncterm.c.sed`, `threadwrap.c.sed`), applied by the
  `Makefile` to a mirror of upstream in `build/gen/`;
- the glue in this directory (`kestrel_*.c`, `kestrel_*.h`, `include/`), the welcome screen `data/BBS.ANS` and
  its generator `mkansi.py`, and the shared layer `../kestrel_sdl2/` (`kestrel_heap.c`, `kestrel_wasi.c`,
  `kestrel_quit.c`, `opt/kestrel_fiber.c`, `opt/kestrel_pthread.c`, `include/kestrel_fiber.h`);
- `Makefile` (the build, its flags and the binaryen 132 `--asyncify` pass) with Zig 0.16.0's `zig cc` and
  binaryen 132.0.0 (npm), which `../fetch.sh` fetches and checks.

Rebuild it from a checkout of this repository:

    apps/ports/fetch.sh
    make -C apps/ports/syncterm link        # build/demo-syncterm.wasm == docs/demo-syncterm.wasm
    make -C apps/ports/syncterm install     # copy it to docs/, repack docs/demo-syncterm.zmd (tools/mkdisks.sh)

The disk is a GEM data disk: GEM boots over it and lists the program, `BOOT.WSM`, beside `WELCOME.ANS` (the fake
BBS's screen, our own CP437 art from `mkansi.py`); a double-click runs SyncTERM, which dials
`telnet://fakebbs.zig` at once (the URL on its command line). Alt+X disconnects; "Save this directory entry?" No
(Enter) quits back to the desktop.

## Layout

| file | what |
|---|---|
| `kestrel_main.c` | the cart's exports: SyncTERM's main is the first fiber; `frame()` runs the fibers, then draws |
| `kestrel_threads.c` | xpdev's `_beginthread` as a fiber (`patches/threadwrap.c.sed`) |
| `kestrel_cio.c` | ciolib's backend: the cells, the mode palette, the cursor, keys (in place of its libretro backend: `patches/ciolib.c.sed`) |
| `kestrel_desk.c` | the cells drawn into plane 0 in the desk mode (or the medium fallback where there is none); only the rows written since the last frame |
| `kestrel_keys.c` | the cart's key exports as ciolib key codes |
| `kestrel_net.h` | the BSD calls SyncTERM makes, and the one interface under them (`struct knet_transport`) |
| `kestrel_sock.c`, `kestrel_resolve.c` | the sockets shim: socket / connect / recv / send / poll / select / ioctl / fcntl / getaddrinfo ... over `knet` |
| `kestrel_fakebbs.c` | the only transport today: a scripted telnet BBS (fakebbs.zig, 10.0.0.2:23) |
| `kestrel_stubs.c` | modem, serial, local shell, HTTPS list download, window icon, termios: not on this machine |
| `kestrel_port.h`, `include/` | force-included fixes for wasi-libc (no signals, no netdb.h, wasip2's socket declarations) |
| `run.mjs` | headless runner: PNGs of the desk, `KEYS="frame:text"`, `CODES="frame:code"` |

Built without cryptlib (no SSH, no telnets, no HTTPS list), OOII, JPEG XL, modem / serial / shell, sound.
The gate's harness is `apps/syncterm_headless.mjs` (`build.sh`, tag `ports_syncterm`).
