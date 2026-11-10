# GEM networking: a virtual network card and GEM's own TCP/IP stack (spec, option B)

Status: **spec**, 9 Nov 2026 (Matt: "can gem have a virtual TCP/IP stack with an ip address and so on?";
option B chosen). Comes after GEMTEST and the GEM 5 file selector / icon fixes (docs/ROADMAP.md).

## 1. Summary

The machine gets a network card, **ZIGNIC**: Ethernet frames in and out, a MAC address, a link bit.
GEM runs a real TCP/IP stack on ZIGGY (**lwIP**, in the ROM) over that card, so GEM has its own IP
address, answers ping, gets its address by DHCP and resolves names by DNS. Programs use a
**STinG-style API** (the TCP/IP stack STs ran on their own 68000), exposed in the GEM 5 program API.
Each host carries ZIGNIC's frames somewhere real:

| Host | Where the frames go | GEM's address |
|---|---|---|
| Board, Wi-Fi | glass ↔ a Linux **TAP** device; Linux routes + NATs it out of `wlan0`; busybox `udhcpd` on the TAP | private, e.g. `10.77.0.2` (gateway `10.77.0.1` = the board) |
| Board, RJ45 (once the PL wires GEM0 through EMIO) | TAP **bridged** to `eth0` | the LAN router's DHCP: a real LAN address |
| Native host (`fpga/host`) | a TAP on the dev machine (needs `ip tuntap`, root once) or a pcap file in tests | as the dev machine routes it |
| Browser | a **WebSocket relay** (frames as binary messages, the technique browser PC emulators use) | the relay's private net |
| Tests / CI | a scripted peer in the harness (ARP, DHCP, ICMP, TCP echo) | fixed |

Why not "sockets handed to Linux" (option A, what the 9 Nov spike does through C:): GEM would have no IP of its
own, no ping, no UDP of its own, and nothing ST-like would run on it. B is the ST's own model (STinG on
the 68000 over a serial/ethernet card), costs only CPU time on ZIGGY, and keeps the seal: the cart sees a
device, never Linux.

## 2. ZIGNIC: the hardware (HW 1.18.0)

A device in the machine like the others (machine/, mirrored by every host), registers in the machine's
register block, frames in **two rings in cart RAM** that the device owns while a descriptor says so
(no DMA engine needed: the host copies).

### Registers (new block, offsets to fix in HW_API.md at implementation)

| Reg | Size | Meaning |
|---|---|---|
| `NIC_ID` | u32 RO | `"ZNIC"`; 0 = no card on this host (the browser without a relay) |
| `NIC_MAC_LO/HI` | u32/u16 RO | the MAC: a locally administered address (`02:5A:4D:..`), fixed per board (from glass), per page in the browser |
| `NIC_STATUS` | u32 RO | bit 0 link up, bit 1 TX ring has room, bit 2 RX frame waiting, bit 8.. dropped-frames count |
| `NIC_CTRL` | u32 | bit 0 enable, bit 1 promiscuous (off), bit 2 IRQ on RX |
| `NIC_TX_RING`, `NIC_RX_RING` | u32 | cart addresses of the two rings (aligned, set once) |
| `NIC_RING_N` | u32 | entries per ring (power of 2, 4..64) |
| `NIC_TX_KICK` | u32 WO | "TX descriptors up to index n are ready" |

### Descriptors

`{ addr: u32, len: u16, flags: u16 }`, frame buffers 1,536 bytes (1,514 + slack). `flags`: OWN (0 = cart,
1 = device), and on RX ERR (frame too long, truncated). The cart fills a TX buffer, sets OWN, kicks; the host
sends it and clears OWN. The cart hands RX buffers with OWN = 1; the host fills one, writes `len`, clears OWN,
sets STATUS bit 2 (and the HBL/VBL-side IRQ if enabled). Ethernet framing is the cart's (no FCS).

### Per host

- **Browser (`docs/sealed-loader.js` + machine wasm):** the loader copies frames between the rings and a
  WebSocket (`?net=ws://host:port`, off by default); no relay = `NIC_ID` 0. The relay is a small script in
  `tools/` (a TAP + NAT on the dev machine, or a userspace NAT like slirp), documented, never public by default.
- **Board:** the firmware (`fpga/cycles/bnic.c`) moves frames between the cart's rings and a **window ring**
  at the top of the cart window (a new block in `fpga/glass/src/map_cart.zig`, as the C: file block is: magic,
  check, sequence, 2 x N slots of 1,536 B: ~100 KB for N = 32 each way). glass (`fpga/glass/src/net_tap.zig`)
  polls it from its own thread and reads/writes `/dev/net/tun`. Polled at ~2 kHz like the C: thread; per frame
  ~1.5 KB at HP0 speeds, so ~1-2 MB/s each way is the expected ceiling, plenty for GEM.
- **Linux image (Buildroot):** `CONFIG_TUN=y`, `CONFIG_BRIDGE=y`, `CONFIG_NETFILTER` + `NF_NAT` + iptables (or
  nftables) for the Wi-Fi NAT, busybox `udhcpd` for the TAP. `S99net` sets up `tap0` 10.77.0.1/24, the NAT out of
  `wlan0` (or the bridge to `eth0`), and the DHCP pool. `KESTREL/net.conf` on the card picks NAT or bridge.
- **Native host:** `fpga/host` maps the rings onto a TAP when `ZM_NET=tap0`, else a scripted peer for tests.

## 3. GEM's stack: lwIP in the ROM

- **lwIP** (BSD licence) in "NO_SYS" mode (no threads): the ROM polls it from the GEM main loop each frame
  (RX ring drain, timers), the way STinG's `TCP_PROC` ran from the VBL. C, compiled with the ROM (rom.wasm →
  rv32 on the board, as the other C in the ROM path is; or a Zig port of a smaller stack if lwIP's C does not
  fit the ROM build — decide at step 2). Budget: ~40-60 KB code, ~32 KB RAM (pbufs, PCBs) in the ROM's arena.
- Enabled: ARP, IPv4, ICMP (ping), UDP, TCP, DHCP client, DNS client. Not now: IPv6, TLS (a later glass-side
  helper, as the spike notes), multicast.
- Config: DHCP by default; a static address from `C:\NET\NET.INF` (`ip=`, `mask=`, `gw=`, `dns=`) when present.
- CPU cost: per-frame stack poll budget ≤ 0.05 Mc idle (the board's 60 fps budget is ~1.75 Mc a frame,
  CLAUDE.md); a bulk TCP transfer is allowed to cost more while it runs. No float.

## 4. The program API (STinG-style, in rom/sdk)

GEM 5 programs (rom/sdk/aes.zig family; a new `rom/sdk/net.zig`) get the calls STinG programs used, with
TOS-style negative error codes:

| Call | STinG analogue | Meaning |
|---|---|---|
| `netStatus()` | `get_dftab`/`TCP_info` | link, our IP/mask/gw/dns, lease time |
| `resolve(name) → ip` | `resolve` | DNS (cached), or a dotted address |
| `tcpOpen(ip, port) → h` | `TCP_open` | active open, non-blocking |
| `tcpListen(port) → h` | `TCP_open` (passive) | one listener per port |
| `tcpState(h)` | `TCP_info` | SYN_SENT / ESTABLISHED / CLOSE_WAIT / closed + error |
| `tcpSend(h, buf) → n`, `tcpRecv(h, buf) → n` | `TCP_send`, `CNget_block` | non-blocking; 0 = would block |
| `tcpClose(h)` | `TCP_close` | |
| `udpOpen(port)`, `udpSendTo`, `udpRecvFrom` | `UDP_open`, ... | |
| `ping(ip) → ms` | `ICMP_send` | for the "what's my IP" demo |

Up to 8 TCP and 4 UDP handles per machine. Nothing blocks: GEM 5 is cooperative, a program polls in its
event loop. These are new system-table entries (bump at implementation).

## 5. Steps, tests and the proof for each

| Step | What | Proof |
|---|---|---|
| N1 | ZIGNIC in the machine + browser scripted peer; HW 1.18.0 | `apps/nic_check.mjs`: TX/RX rings, OWN handover, ring full, oversize frame, `NIC_ID` 0 with no peer; `--break` mutants |
| N2 | Board: `bnic.c` + glass `net_tap.zig` + the window ring; Buildroot TUN/NAT/udhcpd + `S99net` | glass host tests (ring copy, half-written block, TAP stub); on the board: a raw ARP frame from a test cart reaches `tap0` (`tcpdump`-less: glass counters) |
| N3 | lwIP in the ROM, DHCP + ARP + ICMP | harness peer leases 10.77.0.2 and gets a ping reply; board: `ping 10.77.0.2` from the board's Linux answers |
| N4 | TCP/UDP/DNS + the STinG-style API | harness: TCP echo through the peer; board: GEM resolves and connects to tcpbin.com |
| N5 | Demo GEM programs on the GEMTEST pattern: **NETINFO** (address, lease, ping a host) and **TELNET** (a VT52-ish client in a GEM window) | their harnesses; board: telnet to a BBS / the dev laptop |
| N6 | RJ45 bridge mode (needs the PL's EMIO Ethernet, docs/FPGA_GLASS.md) | GEM gets a LAN address from the router |

Rough cost: N1-N2 ~3-4 days, N3-N4 ~1 week, N5 ~3 days, N6 depends on the EMIO wiring (~10 LUT + an IOBUF,
plus the PHY bring-up).

## 6. Risks and decisions to take

- **lwIP's C in the ROM path**: the ROM is Zig compiled to wasm; C in it means the C toolchain step the C carts use
  (`zig cc` to wasm). If that is awkward, a smaller Zig stack (ARP/IPv4/ICMP/UDP/TCP-lite/DHCP/DNS) is the fallback;
  decide at N3 with a size/fit test.
- **Wi-Fi cannot bridge**: a Wi-Fi client cannot carry a second MAC on the LAN, so Wi-Fi is NAT only; LAN-visible
  GEM needs the RJ45 (N6).
- **Security**: GEM's address is private behind the board's NAT by default; no listener is reachable from the LAN
  unless a port forward is set in `KESTREL/net.conf`. The browser relay is off unless `?net=` is given.
- **Window space**: the board's window ring takes ~100 KB at the top of the cart window; check against the
  2 MB cart window budget (hwRamFree) and map_cart.zig's layout asserts.
- **The 9 Nov file spike** (`fpga/glass/src/kos_net.zig`, `.REQ`/`.ANS`) stays as a debug path until N4, then goes.
