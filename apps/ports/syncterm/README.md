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
- exactly the patches in `patches/` (`bbslist.c.sed`, `ciolib.c.sed`, `syncterm.c.sed`, `threadwrap.c.sed`), applied by the
  `Makefile` to a mirror of upstream in `build/gen/`;
- the glue in this directory (`kestrel_*.c`, `kestrel_*.h`, `include/`), the welcome screen `data/BBS.ANS` and
  its generator `mkansi.py`, and the shared layer `../kestrel_sdl2/` (`kestrel_heap.c`, `kestrel_wasi.c`,
  `kestrel_quit.c`, `opt/kestrel_fiber.c`, `opt/kestrel_pthread.c`, `opt/kestrel_wasi_c.c`, `opt/kestrel_wasi_cdir.c`,
  `opt/kestrel_wasi_cfile.c`, `opt/kestrel_wasi_c.h`, `include/kestrel_fiber.h`, `include/kestrel_gemdos.h`), and KOS
  GEMDOS (C:), built from `../../../rom/kos/gemdos_c.zig` and the files it imports;
- `Makefile` (the build, its flags and the binaryen 132 `--asyncify` pass) with Zig 0.16.0's `zig cc` and
  binaryen 132.0.0 (npm), which `../fetch.sh` fetches and checks.

Rebuild it from a checkout of this repository:

    apps/ports/fetch.sh
    make -C apps/ports/syncterm link        # build/demo-syncterm.wasm == docs/demo-syncterm.wasm
    make -C apps/ports/syncterm install     # copy it to docs/, repack docs/demo-syncterm.zmd (tools/mkdisks.sh)

The disk is a GEM data disk: GEM boots over it and lists the program, `BOOT.WSM`, beside `WELCOME.ANS` (the fake
BBS's screen, our own CP437 art from `mkansi.py`) and `DIAL.TXT`; a double-click runs SyncTERM.

## The dialing directory (on C:)

With C: (the card's `HD/` on the board, the page's `?c=` in the browser) SyncTERM opens on its own dialing
directory, kept in `C:\SYNCTERM\` (`SYNCTERM.LST`, the entries; `SYNCTERM.INI`, the settings, written when one
is changed): `kestrel_main.c` starts it with no URL and with upstream's `-n` / `-b` overrides naming those two
files (`kestrel_dialdir.c`). So:

- **Enter** on an entry dials it; **Insert** adds one (name, connection type: Telnet or RLogin, address; a port
  other than 23 is set with F2, Edit), **F2** edits, **Delete** deletes: every change is saved on C: at once.
- A hang-up (**Alt+H**, Yes) or the BBS dropping the call puts you back on the directory, to redial or pick
  another BBS without leaving the program.
- **Alt+X** (or Esc) on the directory quits to the GEM desktop; Alt+X during a call hangs up and quits too.
- The first time (no list on C:), the list is SEEDED: an entry per `telnet://` / `rlogin://` line of the
  floppy's `DIAL.TXT` (committed: `telnet://vert.synchro.net`), plus `fakebbs.zig`, the BBS inside the cart,
  which answers with or without a network card. A BBS of your own (a LAN one) is added with Insert, or by
  editing `C:\SYNCTERM\SYNCTERM.LST` on the card; it never goes in the committed `DIAL.TXT`.

Without C: there is nowhere to keep a directory: SyncTERM dials at once, as the spike did (`telnet://fakebbs.zig`,
or `DIAL.TXT`'s first line when a ZIGNIC card answers), and Alt+X, No quits.

C: writes a file whole (`docs/KOS_GEMDOS.md` §7: `fopen "r+"`, changing a file in place, is refused), so the
three places upstream rewrites the list in place (the LastConnected/TotalCalls update after a connect,
deleting an entry, the comment editor's probe) are patched to read it, then write it again
(`patches/syncterm.c.sed`, `patches/bbslist.c.sed`, `kestrel_rewrite`). Its other paths (XDG cache, downloads)
fall on the read-only floppy and fail quietly, as upstream expects of a missing folder.

The in-cart BBS hangs up when a line `G` (its menu's Goodbye) or `BYE` is typed: the remote drop.

## Layout

| file | what |
|---|---|
| `kestrel_main.c` | the cart's exports: SyncTERM's main is the first fiber (on the directory, or a URL with no C:); `frame()` runs the fibers, then draws |
| `kestrel_dialdir.c` | the dialing directory on C: (`C:\SYNCTERM`): the folder, the seed from `DIAL.TXT`, the whole-file rewrite |
| `kestrel_threads.c` | xpdev's `_beginthread` as a fiber (`patches/threadwrap.c.sed`) |
| `kestrel_cio.c` | ciolib's backend: the cells, the mode palette, the cursor, keys (in place of its libretro backend: `patches/ciolib.c.sed`) |
| `kestrel_desk.c` | the cells drawn into plane 0 in the desk mode (or the medium fallback where there is none); only the rows written since the last frame |
| `kestrel_keys.c` | the cart's key exports as ciolib key codes |
| `kestrel_net.h` | the BSD calls SyncTERM makes, and the one interface under them (`struct knet_transport`) |
| `kestrel_sock.c`, `kestrel_resolve.c` | the sockets shim: socket / connect / recv / send / poll / select / ioctl / fcntl / getaddrinfo ... over `knet` |
| `kestrel_fakebbs.c` | the only transport today: a scripted telnet BBS (fakebbs.zig, 10.0.0.2:23) |
| `kestrel_stubs.c` | modem, serial, local shell, HTTPS list download, window icon, termios: not on this machine; `ftruncate` at a C: file's end |
| `kestrel_port.h`, `include/` | force-included fixes for wasi-libc (no signals, no netdb.h, wasip2's socket declarations) |
| `run.mjs` | headless runner: PNGs of the desk, `KEYS="frame:text"`, `CODES="frame:code"`, `INPUTS="frame:arrow"`, `C=<img>` a C: |

Built without cryptlib (no SSH, no telnets, no HTTPS list), OOII, JPEG XL, modem / serial / shell, sound.
The gate's harnesses (`build.sh`, tag `ports_syncterm`): `apps/syncterm_headless.mjs` (no C:: it dials at once, the
spike's path) and `apps/syncterm_dialdir.mjs` (C:: the directory opens, dials the in-cart BBS, comes back after the
BBS's hang-up and after Alt+H, an entry added is on C: and read back by a second session).
