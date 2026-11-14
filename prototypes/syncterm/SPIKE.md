# SyncTERM spike (9 Nov 2026)

Matt: *"do a spike for syncterm to try to compile it even if the ip stack is mocked up"*. Branch
`port/syncterm-spike`. The port is `apps/ports/syncterm/` (its README: licence, layout, rebuild); the gate is
`apps/syncterm_headless.mjs` (`build.sh` tag `ports_syncterm`). This file is what the spike learnt.

## Result

**It compiles, links and runs**, in the browser's machine (headless: the gate, `apps/scene_hash.mjs`) and
through the native host (`fpga/host`, wasm2c): 120 frames give the same frame hashes on both (total
`529b06d1...`). The board's lean image builds (`make split-cart CART=syncterm ZM_ZMX=1`, table 1.17).
SyncTERM 1.9 starts from GEM, switches to the desk mode
(640x480), dials `telnet://fakebbs.zig`, negotiates telnet (ECHO, SGA, TTYPE "syncterm", NAWS 80x24), draws the
BBS's ANSI screen 1:1 with its own status bar on row 25 and ours under it, echoes typed keys, and Alt+X then No
quits back to the desktop.

What is on screen: a blue double-line frame; "ZIG BBS" in block letters shaded blue to cyan to white; a CP437
shade band; "Node 1 of 1 | KESTREL / ZIGGY at 100 MHz | SyncTERM in the desk mode"; a fake menu ([M]essage
bases, [F]ile areas, [D]oor games, [G]oodbye); then the BBS's line "telnet: terminal syncterm, 80x24" (what the
negotiation told it) and a yellow `>` prompt with what was typed; row 25 is SyncTERM's own bar
("fakebbs.zig | Telnet | Connected: 00:00:02 | ALT-Z for menu"); under the 400 rows of cells, in the desk's
last 80, our status line: "SyncTERM 1.9 - telnet://fakebbs.zig - network: MOCK (an in-cart BBS, no TCP/IP)".
Where the machine has no desk mode (a pre-1.17 bitstream) the plane is medium res and its first line says so.

## How (and what had to change from the plan)

- **Upstream untouched** (sparse checkout of Synchronet at tag `syncterm-1.9`, `apps/ports/fetch.sh`), three sed
  patches: `ciolib.c` (our backend instead of curses / libretro), `syncterm.c` (`main` -> `syncterm_main`; the
  scrollback 2000 -> 100 lines, 2.5 MB -> 128 KB), `threadwrap.c` (`_beginthread` is ours). 75 upstream
  objects: syncterm (13 files), sbbs3 telnet / zmodem / xmodem, uifc, conio (ciolib, cterm, vidmodes, allfonts,
  mouse, utf8_codepages, ansi_cio), xpdev (29), encode, hash. Never ran upstream's Makefiles: the Makefile here
  drives `zig cc` itself.
- **Threads -> fibers.** SyncTERM runs its main, the telnet input and output pumps (`rlogin.c`) and ciolib's
  mouse thread as threads that block in `select`/`poll`, semaphores and condition variables. The shared layer
  got opt-in fibers on binaryen Asyncify (`kestrel_sdl2/src/opt/kestrel_fiber.c`: GrafX2's one coroutine
  generalised: each fiber its own C stack and save area, `__stack_pointer` switched per fiber) and pthread over
  them (`kestrel_pthread.c`: a wait blocks the fiber until its condition can hold; a sleep ends at a frame).
  `frame()` resumes every fiber that can make progress until each blocks. Two traps found on the way: a
  `void (*)(void *)` thread function called as `void *(*)(void *)` traps in wasm (hence our `_beginthread`), and
  the switch function must not be inlined (binaryen leaves the function that calls `start_unwind` uninstrumented:
  inlined into its caller, the caller became the runtime and the rewind hit `unreachable`).
- **Not ciolib's SDL output** (the brief asked for it): `sdl_con.c` and `retro.c` both sit on `bitmap_con.c`,
  which renders every cell to 32-bit pixels: two 640x400 screens of 1 MB plus a 1 MB rectangle per update, more
  than the 3 MiB cart window holds next to SyncTERM. `kestrel_cio.c` is a cell backend (the shape of `curs_cio.c`)
  and `kestrel_desk.c` draws 8-bit indices straight into the desk plane, only the rows written since the last
  frame, a cell compared field by field (cterm leaves stack garbage in a cell's padding). The SDL layer is used
  for what fits: heap, WASI over the floppy, quit; the keys go straight to ciolib codes (`kestrel_keys.c`).
- **The network is one interface.** `kestrel_net.h` renames the BSD calls (object-like macros, so struct members
  such as `conn_api.close` stay consistent) onto `kestrel_sock.c` / `kestrel_resolve.c`, which run over
  `const struct knet_transport *knet`. The fake BBS (`kestrel_fakebbs.c`) is the only transport; ZIGNIC's
  becomes another `knet_transport` (open / state / rx_avail / rx / tx_room / tx / disconnect / resolve map onto
  its OPEN, CONNECT, RX ring, TX ring, CLOSE, RESOLVE), nothing above it changes.

## The BSD calls the shim must provide (N6)

What SyncTERM's telnet / raw / rlogin path calls at run time (`conn.c conn_socket_connect`, `rlogin.c`'s pumps,
xpdev `sockwrap.c socket_check / socket_readable / socket_writable / socket_recvdone`, built with
`PREFER_POLL` as on Linux):

| call | arguments / flags used | semantics needed |
|---|---|---|
| `getaddrinfo` | `hints.ai_family` PF_UNSPEC / PF_INET / PF_INET6 (per BBS entry), `SOCK_STREAM`, `IPPROTO_TCP`, `AI_NUMERICSERV \| AI_ADDRCONFIG`, service = the port as digits | a list; SyncTERM tries each address |
| `freeaddrinfo` | | |
| `socket` | `ai_family, SOCK_STREAM, IPPROTO_TCP` | |
| `ioctl` (`ioctlsocket`) | `FIONBIO` 1 before connect, 0 after | non-blocking connect |
| `connect` | non-blocking | -1 `EINPROGRESS` (also EINTR / EAGAIN / EWOULDBLOCK accepted), then poll for POLLOUT |
| `poll` | 1 fd; `POLLIN`, `POLLIN \| POLLHUP`, `POLLOUT`, `POLLIN \| POLLHUP \| POLLOUT`; timeouts 0, 100, 1000 ms | `revents` POLLIN / POLLOUT / POLLHUP / POLLERR / POLLNVAL; blocks (yields) up to the timeout |
| `recv` | flags 0 (up to the read buffer), and `MSG_PEEK` of 1 byte (is it EOF or data?) | 0 = closed, -1 + `EMSGSIZE` tolerated |
| `send` (`sendsocket`) | flags 0 | partial sends retried |
| `setsockopt` | `SOL_SOCKET, SO_KEEPALIVE, 1` | may be a no-op |
| `shutdown` | `SHUT_RDWR` when a pump ends | |
| `close` (`closesocket`) | | must still close files for every other fd |
| `errno` | `EINPROGRESS`, `EINTR`, `EAGAIN`, `EWOULDBLOCK`, `ENOMEM`, `EMSGSIZE` | read via `ERROR_VALUE` |

Linked but not reached on that path (the shim answers them anyway): `select` (sockwrap without PREFER_POLL),
`getsockopt` (`SO_ERROR`), `getpeername`, `getsockname`, `getnameinfo` (numeric), `gethostbyname`,
`gethostbyaddr`, `fcntl` (`F_GETFL` / `F_SETFL O_NONBLOCK`), `FIONREAD`. Not provided: `bind`, `listen`,
`accept` (xpdev's server helpers and the RIP / SSH paths; never called by the client). SSH and telnets would
add cryptlib (not built), the HTTPS list download `webget.c` the same.

## Stubs (what the spike left out)

| left out | how | why |
|---|---|---|
| SSH, telnets, HTTPS BBS list (cryptlib) | not built (`WITHOUT_CRYPTLIB`); `webget` entry points return false (`kestrel_stubs.c`) | cryptlib is a large port of its own; ZIGNIC's TLS sockets (N4) may replace telnets |
| modem / serial / local shell (`modem.c`, `comio`, `conn_pty.c`) | `modem_connect` / `pty_connect` fail with a log line | no serial port, no processes |
| OOII, JPEG XL, sound (`xpbeep` is linked; `beep` is silent) | not built / no-op | not needed for a terminal spike |
| ciolib's pixel API (`setpixel`, `getpixels`: RIP graphics, sixel, the screen-capture) | NULL in `cio_api` (ciolib answers 0) | the cell backend has no pixels; RIP needs a pixel layer later |
| loadable / custom fonts beyond the built-in ones | built-in `conio_fontdata` only (8x16, or 8x8 doubled) | |
| the mouse | `cio_api.mouse = 0`; `pointer` ignored | |
| the config: `syncterm.ini`, `syncterm.lst`, the cache | not read or written: the XDG paths need a writable home (`mkpath` fails on the read-only floppy) | C: (KOS GEMDOS) is the place for them next |
| `clock_getres`, `ftruncate`, `utime` (WASI) | answered in `kestrel_stubs.c` (the floppy is read-only) | |
| signals, termios | `include/signal.h`, termios stubs | ciolib's ANSI backend is linked but never chosen |

## Sizes (cart window 3 MiB, `hwRamFree`)

- Cart: `docs/demo-syncterm.wasm` 1,337,186 B (1,018,056 before Asyncify: +31 %), 393,560 B ZX0-packed on the disk.
- Static data + stack: 907,136 B of the window (of which `allfonts.c` ~350 KB of glyphs, the C stack 128 KB);
  2,238,592 B left, the heap takes all but 64 KB (2,173,072 B).
- Heap at boot 566,016 B (the fibers: main's 256 KB C stack, 64 KB for each other thread, a 48 KB save area each);
  ~0.77 MB once connected.

- Board: the lean image `cart.bin` is 2,089,440 B (wasm2c rv32, ZM-X), 892,525 B ZX0-packed; staged with the data
  disk in `prototypes/syncterm/card/up/` (`stage_card.py`, `install.sh` as notepad's).

## Cost (apps/frame_cost.mjs, estimate)

- Idle, connected: **est. 0.72 Mc/frame** (cart 0.01 Mc; FRESCO 0.7 is the model's plane, which the desk mode does
  not composite), ~60 fps.
- Typing (a key every 2 frames): est. 0.80 Mc/frame, cart 0.03 Mc (~0.06 Mc a key: one cell drawn).
- The connect frame (the whole ANSI screen arrives and is drawn): max 25.7 Mc, once.
- Before two fixes the same typing cost 3.9 Mc a frame: the mode palette set on every key forced a full redraw.

## What blocks a board build

Nothing found in the spike: the lean image (`make split-cart CART=syncterm ZM_ZMX=1`, system table 1.17) needs no
new import (env imports: `consoleLogJS`, `diskReadBlock`, `hwDeskAvailable`, `hwRamAlloc`, `hwRamFree`,
`hwVideoBase`, `memory`), the desk mode needs HW 1.17.0 (the card's bitstream has it), and `NO_LITERAL_SONGS`
keeps song_pack from reading the cart's strings as songs. Risks: Asyncify's code size on ZIGGY's I$ (the connect
frame), and the ~0.77 MB heap in the board's cart RAM (fine: 12 MiB there).

## Next steps to hook it to ZIGNIC

1. N1-N3: the ZIGNIC registers and rings in the machine, the browser relay, glass's sockets on the board.
2. `kestrel_zignic.c`: a `struct knet_transport` over the 8 hardware sockets (open = OPEN + CONNECT, state =
   the socket's status word, rx / tx = the rings, resolve = RESOLVE on a free socket); `knet` points at it when
   `NIC_ID` is non-zero, else at the fake BBS (kept for the gate). Move `kestrel_sock.c`, `kestrel_resolve.c`,
   `kestrel_net.h` into `kestrel_sdl2/src/opt/` as the N6 shim for every C port.
3. A dialing directory: `syncterm.lst` / `syncterm.ini` on C: (KOS GEMDOS), so SyncTERM starts on its BBS list
   instead of a fixed URL; ZMODEM downloads to C:.
4. TLS (N4): telnets through ZIGNIC's TLS socket mode; SSH needs cryptlib or a small SSH client.
5. RIP and sixel: a pixel layer under the cell backend (ciolib's `setpixel` / `setpixels`) in the desk plane.
