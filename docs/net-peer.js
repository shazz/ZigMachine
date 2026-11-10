// --------------------------------------------------------------------------
// ZIGNIC's scripted network (docs/GEM_NET.md, N1): a small deterministic LAN 10.77.0.0/24 the page and the
// harnesses use when no relay is given (`?net=peer`), so the card and its carts are tested with no network.
// Time is the card's polls, never a clock: a connect is established on the next poll, a timeout after 3.
//
//   10.77.0.1   echo.zig  TCP 7 / 5555 echo, UDP 7 echo, TLS 443 echo (with any host name), ICMP echo
//   10.77.0.3   bbs.zig   TCP 23: a banner, then echo
//   10.77.0.250 slow.zig  TCP: never answers (timeout)
//   other 10.77.0.x       TCP: refused;   anything else: unreachable
//   listen 2323 allowed: an inbound connection arrives 2 polls later and says "hello listener\r\n"
// --------------------------------------------------------------------------
globalThis.ZMNetPeer = (function () {
    const ip = (a, b, c, d) => ((a << 24) | (b << 16) | (c << 8) | d) >>> 0;
    const ECHO = ip(10, 77, 0, 1), BBS = ip(10, 77, 0, 3), SLOW = ip(10, 77, 0, 250);
    const NAMES = { "echo.zig": ECHO, "bbs.zig": BBS, "slow.zig": SLOW };
    const BANNER = "ZIG BBS (scripted peer)\r\n> ";
    const enc = new TextEncoder();

    function parseDotted(s) {
        const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(s);
        if (!m) return null;
        const p = m.slice(1).map(Number);
        return p.some((x) => x > 255) ? null : ip(p[0], p[1], p[2], p[3]);
    }

    function make() {
        const info = { id: 0x5a4e4943, ip: ip(10, 77, 0, 2), mask: ip(255, 255, 255, 0), gw: ECHO, dns: ECHO, flags: 0b111 };
        return {
            info: () => info,
            // A name -> ip, or null (not found). Dotted strings resolve to themselves.
            resolve: (name) => parseDotted(name) ?? NAMES[name.toLowerCase()] ?? null,
            // A TCP/TLS connection: an endpoint object, or a string Err name.
            connect(addr, port, tls) {
                if (addr === SLOW) return "timeout";
                if ((addr >>> 8) !== (ECHO >>> 8)) return "unreachable_";
                if (tls) return addr === ECHO && port === 443 ? echoEndpoint() : "tls";
                if (addr === ECHO && (port === 7 || port === 5555)) return echoEndpoint();
                if (addr === BBS && port === 23) return echoEndpoint(BANNER);
                return "refused";
            },
            // A UDP / ICMP datagram to addr:port -> the reply datagram (bytes) or null (none).
            datagram(addr, port, bytes, icmp) {
                if (addr !== ECHO) return null;
                return icmp || port === 7 ? bytes.slice() : null;
            },
            listenAllowed: (port) => port === 2323,
            inbound: () => echoEndpoint("hello listener\r\n", ip(10, 77, 0, 9), 40000),
        };
    }

    // An endpoint: what the peer has sent (rx) and how it answers what it gets.
    function echoEndpoint(greeting, from, fromPort) {
        const rx = greeting ? Array.from(enc.encode(greeting)) : [];
        return {
            rx,
            peer: from ?? null,
            peerPort: fromPort ?? 0,
            take(bytes) { for (const b of bytes) rx.push(b); }, // echo
            closed: false,
        };
    }

    return { make, ip };
})();
