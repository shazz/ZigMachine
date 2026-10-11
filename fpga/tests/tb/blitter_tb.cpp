// CXXRTL testbench for rtl/blitter/zm_blit.v against the Zig oracle (tests/blitter_ref).
//
//   blitter_tb <script> <expected trace> [fast|random|deep [seed]] [out trace]
//
// The script is the oracle's (see tests/blitter_ref/blitter_ref.zig); the registers are
// written through the CPU port as a CPU writes the region (byte enables, word index), the
// memory behind the master ports is a byte array at the machine's linear addresses, and
// after every `run` the trace line (cycles, status, hash of the whole window) must equal
// the oracle's. `random` answers the ports like a loaded DDR: ready on three clocks in
// four, reads 1 to 4 clocks late, wr_pending up for 0 to 5 clocks after a write; and it
// drops register writes at an op in flight, which the block must ignore. `deep` is
// `random` with the reads 16 to 31 clocks late (an HP port's latency), so the pixel
// unit runs with dozens of reads in flight.
// The memory applies each access when the port takes it (a read and a write in the same
// clock: the read first), which is the port's contract. It also enforces the half of the
// contract a memory cannot see by itself: no write may be taken while an earlier read of
// one of its bytes is still unanswered (soc/zm_blit_hp.py lets writes pass reads).
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "zm_blit.cc"

static cxxrtl_design::p_zm__blit top;
static const uint32_t LO = 0x100000, HI = 0x700000, VIDEO = 0x300000, REGS_END = VIDEO + 0x100;
static const uint8_t PAL[8] = {0, 1, 2, 0x55, 0xAA, 0xFF, 0x0F, 0xF0};
static std::vector<uint8_t> mem(HI, 0);
static uint64_t rng = 1, lcg = 12345;
static bool randomize = false, deep = false;
static long now = 0, bad = 0, pending_until = 0;
struct Rsp { long due; uint32_t data, addr; };
static std::deque<Rsp> rsp_q;

static uint64_t next() { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }
static unsigned rnd(unsigned n) { lcg = lcg * 6364136223846793005ull + 1442695040888963407ull; return unsigned(lcg >> 33) % n; }

static void seed(uint64_t n) {
    rng = n * 0x9E3779B97F4A7C15ull + 1;
    for (uint32_t a = LO; a < HI; a++) {
        uint8_t v = uint8_t(next() >> 16);
        mem[a] = (v & 0xE0) == 0 ? v : PAL[v & 7];
    }
}

static uint64_t hash() {
    uint64_t h = 0xcbf29ce484222325ull;
    for (uint32_t a = LO; a < HI; a += 8) {
        if (a >= VIDEO && a < REGS_END) continue;
        uint64_t w;
        memcpy(&w, &mem[a], 8);
        h = (h ^ w) * 0x100000001b3ull;
        h ^= h >> 29;
    }
    return h;
}

static bool in_window(uint32_t a) { return a >= LO && a < HI; }

static void tick() {
    bool rr = !randomize || rnd(4) != 0, wr = !randomize || rnd(4) != 0;
    top.p_rd__req__ready.set(rr);
    top.p_wr__req__ready.set(wr);
    bool rsp = !rsp_q.empty() && rsp_q.front().due <= now;
    top.p_rd__rsp__valid.set(rsp);
    top.p_rd__rsp__data.set<uint32_t>(rsp ? rsp_q.front().data : 0xDEADBEEF);
    top.p_wr__pending.set(now < pending_until);
    top.step();
    if (rsp) rsp_q.pop_front();
    if (top.p_rd__req__valid.get<bool>() && rr) {
        uint32_t a = top.p_rd__req__addr.get<uint32_t>();
        if (!in_window(a)) bad++;
        else {
            uint32_t w;
            memcpy(&w, &mem[a & ~3u], 4);
            long late = deep ? 16 + long(rnd(16)) : randomize ? long(rnd(4)) : 0;
            rsp_q.push_back({now + 1 + late, w, a});
        }
    }
    if (top.p_wr__req__valid.get<bool>() && wr) {
        uint32_t a = top.p_wr__req__addr.get<uint32_t>(), d = top.p_wr__req__data.get<uint32_t>();
        unsigned strb = top.p_wr__req__strb.get<unsigned>();
        for (const Rsp &r : rsp_q)  // an unanswered earlier read of one of these bytes
            if ((r.addr & ~3u) == a && (strb >> (r.addr & 3) & 1)) {
                std::printf("write %06x strb %x taken over the unanswered read of %06x\n", a, strb, r.addr);
                bad++;
            }
        if (!in_window(a) || (a & 3) || strb == 0 || strb > 15) bad++;
        else
            for (int i = 0; i < 4; i++)
                if (strb >> i & 1) mem[a + i] = uint8_t(d >> (8 * i));
        pending_until = now + 1 + (randomize ? long(rnd(6)) : 0);
    }
    top.p_clk.set(true);
    top.step();
    top.p_clk.set(false);
    top.step();
    now++;
}

static void cpu_write(uint32_t off, unsigned bytes, uint32_t v) {
    uint32_t w = (off - 0x80) / 4, sh = off % 4;
    top.p_cpu__we.set(true);
    top.p_cpu__waddr.set<uint32_t>(w);
    top.p_cpu__be.set<uint32_t>(((1u << bytes) - 1) << sh);
    top.p_cpu__wdata.set<uint32_t>(v << (8 * sh));
    tick();
    top.p_cpu__we.set(false);
}

static uint32_t cpu_read(uint32_t word) {
    top.p_cpu__raddr.set<uint32_t>(word);
    top.step();
    return top.p_cpu__rdata.get<uint32_t>();
}

static long run(unsigned cmd, bool junk, std::string &err) {
    cpu_write(0x80, 1, cmd);
    long t0 = now;
    bool seen = false;
    while (now - t0 < 60000000) {
        bool b = top.p_busy.get<bool>();
        seen |= b;
        if (!b && (seen || now - t0 > 3)) break;
        // a write at an op in flight must be dropped (random mode: junk into COLOR / D_BASE)
        if (junk && b && rnd(16) == 0) cpu_write(rnd(2) ? 0x84 : 0xA0, rnd(2) ? 1 : 4, uint32_t(rnd(1 << 30)));
        else tick();
    }
    if ((cmd >= 1 && cmd <= 4) && !seen) err += " BUSY never rose;";
    if (top.p_busy.get<bool>()) err += " BUSY never fell;";
    return now - t0;
}

int main(int argc, char **argv) {
    if (argc < 3) return std::puts("usage: blitter_tb <script> <expected> [fast|random|deep [seed]] [out]"), 2;
    deep = argc > 3 && !strcmp(argv[3], "deep");
    randomize = deep || (argc > 3 && !strcmp(argv[3], "random"));
    lcg += argc > 4 ? strtoull(argv[4], nullptr, 0) : 0;
    std::ifstream script(argv[1]), expect(argv[2]);
    std::ofstream out(argc > 5 ? argv[5] : "/dev/null");
    top.p_rst.set(true);
    tick(); tick();
    top.p_rst.set(false);
    tick();
    std::string line, want;
    unsigned n = 0, fails = 0;
    while (std::getline(script, line)) {
        std::istringstream it(line.substr(0, line.find('#')));
        std::string op;
        if (!(it >> op)) continue;
        std::string ta, tb;
        it >> ta >> tb;
        uint64_t a = strtoull(ta.c_str(), nullptr, 0), b = strtoull(tb.c_str(), nullptr, 0);
        if (op == "seed") seed(a);
        else if (op == "dump") std::ofstream(ta, std::ios::binary).write((const char *)&mem[LO], HI - LO);
        else if (op[0] == 'w') cpu_write(uint32_t(a), unsigned(atoi(op.c_str() + 1) / 8), uint32_t(b));
        else if (op == "run") {
            std::string err;
            long clk = run(unsigned(a), randomize, err);
            uint32_t cycles = cpu_read(24), status = cpu_read(0) >> 24;
            char got[128];
            snprintf(got, sizeof got, "R %u %u %u %016llx", n, cycles, status, (unsigned long long)hash());
            out << got << ' ' << clk << " cmd " << a << '\n';
            std::getline(expect, want);
            if (want != got || !err.empty() || bad) {
                std::printf("MISMATCH op %u (cmd %llu):\n  want %s\n  got  %s%s\n  bad accesses %ld\n", n, (unsigned long long)a,
                            want.c_str(), got, err.c_str(), bad);
                if (++fails >= 3) return 1;
            }
            n++;
        }
    }
    std::printf("blitter_tb: %u ops, %u mismatches\n", n, fails);
    return fails != 0;
}
