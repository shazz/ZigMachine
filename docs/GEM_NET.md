# GEM networking: ZIGNIC, a socket-offload network card (spec)

Status: **spec**, 9 Nov 2026. Comes after GEMTEST and the GEM 5 file selector / low-res icon fixes
(docs/ROADMAP.md). Matt, 9 Nov: "can gem have a virtual TCP/IP stack with an ip address and so on?", then:
"the goal is to handle most of the network on the ARM and just to get a virtual card on the kestrel, but the
heavy communication is done by the arm" — the way the C64 and Atari 8-bit get networked today: a small
computer in a cartridge does everything (WiC64: an ESP32 on the C64's user port; FujiNet: an ESP32 on the
Atari's SIO bus, with its `N:` device that opens `N:TCP://host:port` or `N:HTTPS://...` URLs itself), and the
8-bit CPU only sends commands and moves bytes. On KESTREL the "cartridge computer" is the ARM.

## 1. Summary

The machine gets a network card, **ZIGNIC**, modelled on the real socket-offload chips retro machines used
(WIZnet W5100/W5500: the Apple II's Uthernet II, Spectrum/C64 cards): the TCP/IP stack is **in the card**,
the CPU only drives **8 hardware sockets** through registers and shared buffers. On KESTREL "the card" is
the ARM: glass runs every socket on Linux's own stack. ZIGGY does no protocol work at all: no TCP state
machine, no retransmits, no checksums, no DNS, no TLS.

- The card has an address: GEM sees **its own IP** (the card's), mask, gateway and DNS in `netStatus`.
- Beyond a W5500, the card also offloads **DNS** (a resolve command) and **TLS** (a socket mode: glass speaks
  TLS to the peer, the cart sees plaintext), so ports like a web browser need no crypto on ZIGGY.
- Programs use a **STinG-style API** (rom/sdk/net.zig) that maps nearly one-to-one onto the socket commands;
  C ports get a **BSD sockets shim** on top (with Asyncify, a blocking call yields to the frame loop).

| Host | Who runs the sockets | GEM's address |
|---|---|---|
| Board (Wi-Fi now, RJ45 later) | glass, Linux sockets out of `wlan0` / `eth0` | the board's own address (the card shares it, as a W5500 behind its own IP would on a NAT); optional: a second address later (§6) |
| Native host (`fpga/host`) | the dev machine's sockets | the dev machine's |
| Browser | a **WebSocket relay** that opens the TCP/UDP connections for the page (`?net=ws://...`, off by default); no relay: `NIC_ID` 0 | the relay's |
| Tests / CI | a scripted peer in the harness (echo, refuse, timeout, DNS table, TLS stub) | fixed |

Why the offload model: the ARM is a 666 MHz Cortex-A9 with Linux's stack, TLS and DNS for free; ZIGGY's 100 MHz
stays for GEM and carts. It is also the authentic choice for an 80s/90s machine card. The cost of putting lwIP
in the ROM (40-60 KB, a per-frame poll, TLS on rv32) disappears.

## 2. The card (HW 1.18.0)

### Common registers (machine register block; offsets fixed in HW_API.md at N1)

| Reg | Size | Meaning |
|---|---|---|
| `NIC_ID` | u32 RO | `"ZNIC"`; 0 = no card on this host |
| `NIC_MAC_LO/HI` | u32/u16 RO | a locally administered MAC (`02:5A:4D:..`), shown as on a real card |
| `NIC_IP`, `NIC_MASK`, `NIC_GW`, `NIC_DNS` | u32 RO | the card's addressing (from the host: DHCP of the board, or static from `KESTREL/net.conf`) |
| `NIC_STATUS` | u32 RO | bit 0 link up, bit 1 address bound, bit 2 any socket has an event |
| `NIC_IRQ_MASK` | u32 | which sockets' events raise the cart IRQ (off by default: GEM polls) |

### 8 sockets, each a register set + a TX and an RX buffer in cart RAM

| Reg | Meaning |
|---|---|
| `Sn_MODE` | CLOSED / TCP / UDP / ICMP (ping) / **TLS** (TCP + TLS by the card, SNI = `Sn_HOST`) |
| `Sn_CMD` (WO) | OPEN, CONNECT, LISTEN, SEND, RECV (ack bytes consumed), DISCON, CLOSE, **RESOLVE** (name → `Sn_DIP`) |
| `Sn_STATUS` | CLOSED, INIT, LISTEN, SYN_SENT, ESTABLISHED, CLOSE_WAIT, UDP, RESOLVED, plus an error code (refused, timeout, unreachable, TLS failure, name not found) |
| `Sn_PORT`, `Sn_DIP`, `Sn_DPORT` | local port, peer address and port (UDP: the last datagram's sender) |
| `Sn_HOST` | cart address + length of a host name (RESOLVE, TLS SNI) |
| `Sn_TX_BASE/SIZE`, `Sn_TX_WR`, `Sn_TX_RD` | a TX ring in cart RAM: the cart writes and moves WR, then SEND; the card moves RD as it takes bytes |
| `Sn_RX_BASE/SIZE`, `Sn_RX_WR`, `Sn_RX_RD` | an RX ring: the card writes and moves WR, the cart reads and moves RD, then RECV |
| `Sn_EVENT` | sticky bits: connected, data in, sent, disconnected, timeout, resolved; write 1 to clear |

Buffers are cart RAM the cart chooses (2-16 KB per socket per direction, as a W5500's 16 KB per direction
split over sockets). UDP frames in the RX ring carry a small header (sender IP, port, length), W5500-style.

### Per host

- **Board:** the firmware (`fpga/cycles/bnic.c`) mirrors the 8 socket register sets and copies ring bytes
  between the cart's buffers and a **window block** at the top of the cart window (a new block in
  `fpga/glass/src/map_cart.zig` like the C: file block: magic, check, sequence, per-socket command/status words
  and staging buffers, ~64 KB). glass (`fpga/glass/src/net_card.zig`, its own thread, ~2 kHz poll like the C:
  thread) runs each socket on Linux: non-blocking `socket/connect/send/recv`, `getaddrinfo` for RESOLVE, an ICMP
  datagram socket for ping, Zig's `std.crypto.tls` client for TLS (glass is Zig, so no OpenSSL is needed).
  Throughput is bounded by the poll and the HP0 copies: ~1-2 MB/s per direction expected, ample for GEM.
- **Linux image:** nothing beyond the Wi-Fi image (feat/board-wifi) for the shared-address mode: glass's sockets
  use the board's address. A CA bundle for TLS (`ca-certificates` in Buildroot) and the clock set by NTP
  (busybox `ntpd`) so certificates validate.
- **Browser:** `docs/sealed-loader.js` serves the socket registers from the page; each socket is a message
  stream over one WebSocket to the relay (`tools/net_relay.py`, run locally; it opens the real TCP/UDP
  connections). No relay: `NIC_ID` 0 and programs say "no network card".
- **Native host:** `fpga/host/net_card.c` on the dev machine's sockets; the harness peer for tests.

## 3. The program API (STinG-style, rom/sdk/net.zig)

A thin layer over the card (no stack in the ROM): handles = socket numbers, TOS-style negative errors, nothing
blocks (GEM 5 is cooperative: a program polls in its event loop).

| Call | STinG analogue | On the card |
|---|---|---|
| `netStatus()` | `get_dftab` / `TCP_info` | `NIC_ID`, `NIC_IP`.., `NIC_STATUS` |
| `resolve(name) → ip` | `resolve` | RESOLVE on a free socket, poll RESOLVED |
| `tcpOpen(ip, port)` / `tlsOpen(name, port)` | `TCP_open` | MODE TCP / TLS, OPEN, CONNECT |
| `tcpListen(port)` | `TCP_open` (passive) | LISTEN (board: only with a port forward set, §5) |
| `tcpState(h)` | `TCP_info` | `Sn_STATUS` |
| `tcpSend(h, buf) → n`, `tcpRecv(h, buf) → n` | `TCP_send`, `CNget_block` | ring copy + SEND / RECV; 0 = would block |
| `tcpClose(h)` | `TCP_close` | DISCON, CLOSE |
| `udpOpen(port)`, `udpSendTo`, `udpRecvFrom` | `UDP_open`, ... | MODE UDP |
| `ping(ip) → ms` | `ICMP_send` | MODE ICMP |

New system-table entries (bump at N3). The **BSD sockets shim** for C ports (`prototypes/kestrel_sdl2` layer):
`socket/connect/bind/listen/accept/send/recv/close/select/poll/getaddrinfo/gethostbyname`, blocking calls
yield through Asyncify, `SSL_*`-like TLS through `tlsOpen` (a small shim, not OpenSSL).

## 4. Steps, tests and the proof for each

| Step | What | Proof |
|---|---|---|
| N1 | ZIGNIC registers + rings in the machine; browser + harness scripted peer; HW 1.18.0 | `apps/nic_check.mjs`: open/connect/send/recv/close, ring wrap, full ring, refused, timeout, RESOLVE, UDP header, `NIC_ID` 0; `--break` mutants |
| N2 | Board: `bnic.c` + glass `net_card.zig` + the window block; NTP + CA bundle in the image | glass host tests (a loopback peer, as kos_net_test.zig does now); board: a test cart connects to the dev laptop's echo |
| N3 | The API in rom/sdk/net.zig + system table entries | harness: a GEM 5 program echoes through the peer |
| N4 | TLS sockets (glass `std.crypto.tls`) and DNS; **NETINFO** GEM program (address, DNS, ping, an HTTPS fetch of a page's title) | board: NETINFO pings and fetches over HTTPS |
| N5 | **TELNET** GEM program (VT52/ANSI in a GEM window) | board: telnet to the dev laptop / a BBS |
| N6 | The BSD sockets shim + a curses-on-SDL text layer for C ports | a small C test cart: `getaddrinfo` + `connect` + `select` |
| N7 | Ports (each its own cart, licence checked first): **SyncTERM** first (GPLv2 C, SDL backend; ANSI-BBS, Atari ST VT52, ATASCII, PETSCII, RIP; X/Y/ZModem to C:; no SSH at first; in the **desk mode**: 80x25 x 8x16 CP437 = 640x400 at 1:1 in 640x480, status line below), an **IRC** client, a **Gopher** client, **Lynx** or **Links** (web over TLS sockets) | each on the board against a live server |
| N7b (option) | A FujiNet-style **URL mode**: `Sn_MODE` URL, `Sn_HOST` = `https://...` / `tcp://...` / `ssh://...`; the card does HTTP(S) (GET/POST, redirects, chunking) and SSH itself, the cart reads the body or the session bytes | NETINFO fetches a page by URL; an SSH session to the dev laptop |
| N8 (option) | A second address for the card (a TAP + NAT or a bridge on the RJ45) and raw-frame mode, for programs that want their own stack | GEM's address differs from the board's |

Rough cost: N1-N3 ~1 week, N4-N5 ~4 days, N6 ~3 days, N7 per port 2-5 days.

## 5. Security and limits

- Outbound by default. LISTEN on the board only for ports named in `KESTREL/net.conf` (`forward=`); a cart cannot
  open a listener on the LAN otherwise.
- The browser relay is off unless `?net=` is given, and binds to localhost by default.
- TLS: glass validates certificates (CA bundle, NTP clock); a cart may ask for "insecure" per socket only through
  an explicit mode bit, shown by NETINFO.
- The card shares the board's address in the default mode: what a cart connects to sees the board.

## 6. Decisions to take

- **Shared address vs a second address** (N8): sharing needs no Linux plumbing; a second address (a TAP with NAT
  over Wi-Fi, or a bridge on the RJ45 once the PL wires GEM0 through EMIO) makes GEM a separate host on the LAN.
- **Window space**: the board's window block (~64 KB) against the 2 MB cart window budget (hwRamFree) and
  map_cart.zig's layout asserts.
- **The 9 Nov file spike** (`fpga/glass/src/kos_net.zig`, `.REQ`/`.ANS`) stays as a debug path until N3, then goes.
