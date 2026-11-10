// ZIGNIC N1 (docs/GEM_NET.md): the page's card (docs/net-host.js) over its scripted LAN (docs/net-peer.js),
// driven exactly as a cart drives it: a Req of 16 little-endian words in a memory, env.netOp(addr).
// Covers: info, TCP connect -> established on the next poll, send/recv echo, the BBS banner, refused,
// unreachable, timeout after 3 polls, resolve (name, dotted, not found), UDP echo with the sender,
// ICMP echo, TLS with and without a name, listen denied / allowed + accept of the inbound call, all 8
// sockets then no_socket, a bad socket, a buffer outside memory, and no card at all.
//   node apps/net_check.mjs [--break noecho|writeback|blocking]
import "../docs/net-peer.js";
import "../docs/net-host.js";

const brk = process.argv.includes("--break") ? process.argv[process.argv.indexOf("--break") + 1] : null;
const { OP, MODE, ST, EV, ERR } = ZMNet;
const mem = new ArrayBuffer(1 << 16);
const REQ = 0x100, BUF = 0x1000, HOST = 0x800, INFO = 0x200;
let fails = 0;
const ok = (cond, what) => { if (!cond) { fails++; console.log("FAIL " + what); } };

function peer() {
    const p = ZMNetPeer.make();
    if (brk === "noecho") { const c = p.connect; p.connect = (...a) => { const e = c(...a); if (typeof e === "object") e.take = () => {}; return e; }; }
    return p;
}
let card = ZMNet.make(() => mem, peer());
if (brk === "writeback") { const c = card; card = (req) => { const save = new Uint8Array(mem, req + 32, 32).slice(); const r = c(req); new Uint8Array(mem, req + 32, 32).set(save); return r; }; }
if (brk === "blocking") { const c = card; card = (req) => { const r = c(req); return r === ERR.again ? 0 : r; }; }

const dv = () => new DataView(mem);
function call(fields) {
    new Uint8Array(mem, REQ, 64).fill(0);
    const names = ["op", "sock", "a0", "a1", "buf", "len", "host", "host_len"];
    names.forEach((k, i) => dv().setUint32(REQ + i * 4, (fields[k] ?? 0) >>> 0, true));
    const r = card(REQ);
    const w = (i) => dv().getUint32(REQ + i * 4, true);
    return { r, state: w(8), events: w(9), err: w(10) | 0, peer: w(11), port: w(12) };
}
const put = (at, s) => { const b = new TextEncoder().encode(s); new Uint8Array(mem, at, b.length).set(b); return b.length; };
const get = (at, n) => new TextDecoder().decode(new Uint8Array(mem, at, n));
const ip = ZMNetPeer.ip;
const open = (mode) => call({ op: OP.open, a0: mode }).r;
function connect(mode, addr, port, name) {
    const s = open(mode);
    const hl = name ? put(HOST, name) : 0;
    const c = call({ op: OP.connect, sock: s, a0: addr, a1: port, host: HOST, host_len: hl });
    return { s, first: c.r };
}
const poll = (s) => call({ op: OP.poll, sock: s });

// info
ok(call({ op: OP.info, buf: INFO, len: 24 }).r === 1, "info answers 1");
ok(dv().getUint32(INFO, true) === 0x5a4e4943 && dv().getUint32(INFO + 4, true) === ip(10, 77, 0, 2), "info: ZNIC at 10.77.0.2");

// TCP echo: in progress, then established, then the bytes come back
let { s, first } = connect(MODE.tcp, ip(10, 77, 0, 1), 7);
ok(first === ERR.again, "connect is non-blocking (again)");
let p = poll(s);
ok(p.state === ST.established && (p.events & EV.connected), "established on the next poll");
const n = put(BUF, "hello KESTREL\r\n");
ok(call({ op: OP.send, sock: s, buf: BUF, len: n }).r === n, "send takes every byte");
ok(poll(s).events & EV.data, "data event after the echo");
let r = call({ op: OP.recv, sock: s, buf: BUF + 0x400, len: 256 });
ok(r.r === n && get(BUF + 0x400, n) === "hello KESTREL\r\n", "recv gives the echo back");
ok(call({ op: OP.recv, sock: s, buf: BUF + 0x400, len: 256 }).r === 0, "recv: 0 when nothing waits");
ok(call({ op: OP.close, sock: s }).r === 0 && call({ op: OP.poll, sock: s }).r === ERR.bad_socket, "close frees the socket");

// The BBS banner
({ s } = connect(MODE.tcp, ip(10, 77, 0, 3), 23)); poll(s);
r = call({ op: OP.recv, sock: s, buf: BUF, len: 64 });
ok(r.r > 0 && get(BUF, r.r).startsWith("ZIG BBS"), "the BBS sends its banner");
call({ op: OP.close, sock: s });

// Refused, unreachable, timeout
({ s } = connect(MODE.tcp, ip(10, 77, 0, 1), 80)); p = poll(s);
ok(p.state === ST.failed && p.err === ERR.refused, "a closed port is refused");
call({ op: OP.close, sock: s });
({ s } = connect(MODE.tcp, ip(1, 2, 3, 4), 80)); p = poll(s);
ok(p.state === ST.failed && p.err === ERR.unreachable_, "off the LAN is unreachable");
call({ op: OP.close, sock: s });
({ s } = connect(MODE.tcp, ip(10, 77, 0, 250), 80));
ok(poll(s).state === ST.connecting && poll(s).state === ST.connecting, "a silent host stays connecting");
p = poll(s);
ok(p.state === ST.failed && p.err === ERR.timeout, "then times out (3 polls)");
call({ op: OP.close, sock: s });

// Resolve
for (const [name, want] of [["bbs.zig", ip(10, 77, 0, 3)], ["10.77.0.1", ip(10, 77, 0, 1)], ["nope.zig", null]]) {
    s = open(MODE.resolve);
    ok(call({ op: OP.resolve, sock: s, host: HOST, host_len: put(HOST, name) }).r === ERR.again, "resolve " + name + " is non-blocking");
    p = poll(s);
    ok(want == null ? p.state === ST.failed && p.err === ERR.not_found : p.state === ST.resolved && p.peer === want, "resolve " + name);
    call({ op: OP.close, sock: s });
}

// UDP and ICMP echo
for (const mode of [MODE.udp, MODE.icmp]) {
    s = open(mode);
    call({ op: OP.sendto, sock: s, a0: ip(10, 77, 0, 1), a1: 7, buf: BUF, len: put(BUF, "ping!") });
    r = call({ op: OP.recv, sock: s, buf: BUF + 0x100, len: 64 });
    ok(r.r === 5 && get(BUF + 0x100, 5) === "ping!" && r.peer === ip(10, 77, 0, 1), (mode === MODE.udp ? "UDP" : "ICMP") + " echo with its sender");
    call({ op: OP.close, sock: s });
}

// TLS: a name is required, the echo answers on 443
s = open(MODE.tls);
ok(call({ op: OP.connect, sock: s, a0: ip(10, 77, 0, 1), a1: 443 }).r === ERR.invalid, "TLS without a host name is invalid");
call({ op: OP.close, sock: s });
({ s } = connect(MODE.tls, ip(10, 77, 0, 1), 443, "echo.zig"));
ok(poll(s).state === ST.established, "TLS to echo.zig:443 established");
call({ op: OP.close, sock: s });

// Listen: denied, then allowed with an inbound call to accept
s = open(MODE.tcp);
ok(call({ op: OP.listen, sock: s, a1: 80 }).r === ERR.denied, "listen on a port not allowed is denied");
call({ op: OP.close, sock: s });
s = open(MODE.tcp);
ok(call({ op: OP.listen, sock: s, a1: 2323 }).r === 0, "listen 2323 allowed");
ok(call({ op: OP.accept, sock: s }).r === ERR.again, "nothing to accept yet");
p = poll(s);
ok(p.events & EV.accept, "an inbound call arrives");
const c2 = call({ op: OP.accept, sock: s }).r;
r = call({ op: OP.recv, sock: c2, buf: BUF, len: 64 });
ok(c2 >= 0 && get(BUF, r.r) === "hello listener\r\n", "accept gives the caller's socket and its bytes");
call({ op: OP.close, sock: c2 }); call({ op: OP.close, sock: s });

// All 8 sockets, a bad socket, a buffer outside memory, no card
const all = Array.from({ length: 8 }, () => open(MODE.udp));
ok(all.every((x) => x >= 0) && open(MODE.udp) === ERR.no_socket, "8 sockets, then no_socket");
all.forEach((x) => call({ op: OP.close, sock: x }));
ok(call({ op: OP.poll, sock: 9 }).r === ERR.bad_socket, "socket 9 is bad");
s = open(MODE.udp);
ok(call({ op: OP.sendto, sock: s, a0: ip(10, 77, 0, 1), a1: 7, buf: mem.byteLength - 2, len: 16 }).r === ERR.invalid, "a buffer past memory is invalid");
call({ op: OP.close, sock: s });
ok(ZMNet.make(() => mem, null)(REQ) === ERR.no_card, "no network: no_card");

console.log(fails ? `net_check: ${fails} FAILED` + (brk ? ` (--break ${brk}: caught)` : "") : "net_check: all checks passed");
process.exit(brk ? (fails ? 0 : 1) : (fails ? 1 : 0));
