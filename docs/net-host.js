// --------------------------------------------------------------------------
// ZIGNIC on the page and in node's harnesses (docs/GEM_NET.md): the host half of env.netOp. The cart writes a
// Req (machine/sdk/net_abi.zig: 16 little-endian words) in its memory and passes its address; this answers at
// once (>= 0 a value, < 0 an Err) and writes the socket's state, events and peer back into the Req. The network
// behind the 8 sockets is pluggable: docs/net-peer.js (a scripted LAN, `?net=peer`) today, a WebSocket relay later.
//
//   const op = ZMNet.make(() => memory.buffer, ZMNetPeer.make());   env.netOp = op;
// --------------------------------------------------------------------------
globalThis.ZMNet = (function () {
    const SOCKETS = 8, IO_MAX = 16384, HOST_MAX = 255;
    const OP = { info: 0, open: 1, connect: 2, listen: 3, send: 4, recv: 5, sendto: 6, poll: 7, close: 8, resolve: 9, accept: 10 };
    const MODE = { tcp: 1, udp: 2, icmp: 3, tls: 4, resolve: 5 };
    const ST = { closed: 0, open: 1, connecting: 2, established: 3, listen: 4, close_wait: 5, resolving: 6, resolved: 7, failed: 8 };
    const EV = { connected: 1, data: 2, sent: 4, closed: 8, resolved: 16, accept: 32, error: 64 };
    const ERR = { no_card: -1, bad_socket: -2, invalid: -3, again: -4, refused: -5, timeout: -6, unreachable_: -7,
        not_found: -8, closed: -9, no_socket: -10, tls: -11, denied: -12 };
    const W = { op: 0, sock: 1, a0: 2, a1: 3, buf: 4, len: 5, host: 6, host_len: 7, state: 8, events: 9, err: 10,
        peer_ip: 11, peer_port: 12, local_port: 13 };
    const TIMEOUT_POLLS = 3, INBOUND_POLLS = 2;

    function make(cartBuffer, net) {
        const socks = Array.from({ length: SOCKETS }, () => null);
        const dec = new TextDecoder();

        function words(at) { return new DataView(cartBuffer(), at, 64); }
        const rd = (v, k) => v.getUint32(W[k] * 4, true);
        const wr = (v, k, x) => v.setUint32(W[k] * 4, x >>> 0, true);
        function bytes(at, n) {
            const b = cartBuffer();
            return at + n <= b.byteLength ? new Uint8Array(b, at, n) : null;
        }
        function writeBack(v, s) {
            wr(v, "state", s ? s.state : ST.closed);
            wr(v, "events", s ? s.events : 0);
            wr(v, "err", s ? s.err : 0);
            wr(v, "peer_ip", s ? s.peer : 0);
            wr(v, "peer_port", s ? s.peerPort : 0);
            wr(v, "local_port", s ? s.local : 0);
            if (s) s.events = 0;
        }
        function fail(s, e) { s.state = ST.failed; s.err = ERR[e]; s.events |= EV.error; return ERR[e]; }

        // Time moves on every op on a socket: a connect lands, a lookup answers, an inbound call arrives.
        function tick(s) {
            s.polls++;
            if (s.state === ST.connecting) {
                const r = s.pending;
                if (r === "timeout") { if (s.polls >= TIMEOUT_POLLS) fail(s, "timeout"); return; }
                if (typeof r === "string") { fail(s, r); return; }
                s.ep = r; s.state = ST.established; s.events |= EV.connected | EV.sent;
            } else if (s.state === ST.resolving) {
                if (s.answer == null) { fail(s, "not_found"); return; }
                s.peer = s.answer; s.state = ST.resolved; s.events |= EV.resolved;
            } else if (s.state === ST.listen && !s.waiting && s.polls >= INBOUND_POLLS && !s.served) {
                s.waiting = net.inbound(); s.served = true; s.events |= EV.accept;
            }
            if (s.ep && s.ep.rx.length) s.events |= EV.data;
        }

        function op(req) {
            if (!net) return ERR.no_card;
            const v = words(req >>> 0);
            const code = rd(v, "op"), n = rd(v, "sock");
            if (code === OP.info) return info(v);
            if (code === OP.open) return open(v);
            const s = n < SOCKETS ? socks[n] : null;
            if (!s) { writeBack(v, null); return ERR.bad_socket; }
            tick(s);
            const r = dispatch(code, v, s, n);
            writeBack(v, socks[n]);
            return r;
        }

        function info(v) {
            const i = net.info(), out = bytes(rd(v, "buf"), 24);
            if (!out || rd(v, "len") < 24) return ERR.invalid;
            const d = new DataView(out.buffer, out.byteOffset, 24);
            [i.id, i.ip, i.mask, i.gw, i.dns, i.flags].forEach((x, k) => d.setUint32(k * 4, x >>> 0, true));
            return 1;
        }

        function open(v) {
            const mode = rd(v, "a0");
            if (!Object.values(MODE).includes(mode)) return ERR.invalid;
            const n = socks.indexOf(null);
            if (n < 0) return ERR.no_socket;
            socks[n] = { mode, state: ST.open, events: 0, err: 0, peer: 0, peerPort: 0, local: rd(v, "a1") || 49152 + n,
                polls: 0, ep: null, dgrams: [] };
            writeBack(v, socks[n]);
            return n;
        }

        function dispatch(code, v, s, n) {
            switch (code) {
                case OP.poll: return s.state;
                case OP.close: socks[n] = null; return 0;
                case OP.connect: return connect(v, s);
                case OP.resolve: return resolve(v, s);
                case OP.send: return send(v, s);
                case OP.recv: return recv(v, s);
                case OP.sendto: return sendto(v, s);
                case OP.listen: return listen(v, s);
                case OP.accept: return accept(s);
                default: return ERR.invalid;
            }
        }

        function hostName(v) {
            const len = rd(v, "host_len");
            const b = len > 0 && len <= HOST_MAX ? bytes(rd(v, "host"), len) : null;
            return b ? dec.decode(b) : null;
        }

        function connect(v, s) {
            if (s.mode !== MODE.tcp && s.mode !== MODE.tls) return ERR.invalid;
            if (s.state !== ST.open) return ERR.invalid;
            const tls = s.mode === MODE.tls;
            if (tls && hostName(v) == null) return ERR.invalid;
            s.peer = rd(v, "a0"); s.peerPort = rd(v, "a1") & 0xffff;
            s.pending = net.connect(s.peer, s.peerPort, tls);
            s.state = ST.connecting; s.polls = 0;
            return ERR.again; // in progress: poll until established (or failed)
        }

        function resolve(v, s) {
            if (s.mode !== MODE.resolve || s.state !== ST.open) return ERR.invalid;
            const name = hostName(v);
            if (name == null) return ERR.invalid;
            s.answer = net.resolve(name); s.state = ST.resolving;
            return ERR.again;
        }

        function send(v, s) {
            if (s.state !== ST.established) return s.state === ST.connecting ? 0 : ERR.closed;
            const len = Math.min(rd(v, "len"), IO_MAX), b = bytes(rd(v, "buf"), len);
            if (!b) return ERR.invalid;
            s.ep.take(Array.from(b)); s.events |= EV.sent;
            return len;
        }

        function recv(v, s) {
            const b = bytes(rd(v, "buf"), Math.min(rd(v, "len"), IO_MAX));
            if (!b) return ERR.invalid;
            if (s.mode === MODE.udp || s.mode === MODE.icmp) return recvDatagram(v, s, b);
            if (!s.ep) return s.state === ST.failed ? s.err : 0;
            const k = Math.min(b.length, s.ep.rx.length);
            b.set(s.ep.rx.splice(0, k));
            return k;
        }

        function recvDatagram(v, s, b) {
            const d = s.dgrams.shift();
            if (!d) return 0;
            const k = Math.min(b.length, d.bytes.length);
            b.set(d.bytes.subarray(0, k));
            s.peer = d.from; s.peerPort = d.port;
            return k;
        }

        function sendto(v, s) {
            if (s.mode !== MODE.udp && s.mode !== MODE.icmp) return ERR.invalid;
            const len = Math.min(rd(v, "len"), IO_MAX), b = bytes(rd(v, "buf"), len);
            if (!b) return ERR.invalid;
            const to = rd(v, "a0"), port = rd(v, "a1") & 0xffff;
            const reply = net.datagram(to, port, b, s.mode === MODE.icmp);
            if (reply) { s.dgrams.push({ bytes: reply, from: to, port }); s.events |= EV.data; }
            return len;
        }

        function listen(v, s) {
            if (s.mode !== MODE.tcp || s.state !== ST.open) return ERR.invalid;
            if (!net.listenAllowed(rd(v, "a1") & 0xffff)) return ERR.denied;
            s.local = rd(v, "a1") & 0xffff; s.state = ST.listen; s.polls = 0;
            return 0;
        }

        function accept(s) {
            if (s.state !== ST.listen) return ERR.invalid;
            if (!s.waiting) return ERR.again;
            const n = socks.indexOf(null);
            if (n < 0) return ERR.no_socket;
            const ep = s.waiting; s.waiting = null;
            socks[n] = { mode: MODE.tcp, state: ST.established, events: EV.connected | EV.data, err: 0, peer: ep.peer,
                peerPort: ep.peerPort, local: s.local, polls: 0, ep, dgrams: [] };
            return n;
        }

        op.sockets = socks;
        return op;
    }

    return { make, OP, MODE, ST, EV, ERR, W };
})();
