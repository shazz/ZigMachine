// CXXRTL testbench for rtl/blitter/zm_blit.v against the Zig oracle (tests/blitter_ref).
//
//   blitter_tb <script> <expected trace> [fast|random|deep [seed]] [out trace]
//
// The script is the oracle's (see tests/blitter_ref/blitter_ref.zig); the registers are
// written through the CPU port as a CPU writes the region (byte enables, word index), the
// QUEUE ring through the ring port, both mirrored into the memory (blitter_tb_mem.h) where
// a CPU store also lands; after every `run` the trace line (cycles, status, hash of the whole
// window) must equal the oracle's. `random` answers the ports like a loaded DDR, and while an
// op is in flight it stores the script's NEXT registers early, as a cart does while CHISEL
// runs: the op must not see them, the next one must. Never while a kick copies the block
// (`copying`): on the board the firmware's load of BLIT_WINDOW after GO waits that out.
// `deep` is `random` with the reads 16 to 31 clocks late (an HP port's latency).
// A `run 5` (QUEUE) is kicked as the firmware does (cycles/bchisel.c): the list's start and
// count from the block's Q_START / Q_COUNT into the kick's word, or refused (CYCLES 0).
#include <fstream>
#include <sstream>
#include <string>

#include "blitter_tb_mem.h"

static const uint32_t RING = 0x1DC000, RING_WORDS = 512, Q_START = 0xE8, Q_COUNT = 0xEA, QUEUE = 5;
struct Op { std::string op; uint64_t a, b; };
static std::vector<Op> ops;
static size_t pc = 0;
static uint8_t blk[0x100];  // the register block as the CPU stored it (the firmware reads it)

static void cpu_write(uint32_t off, unsigned bytes, uint32_t v) {
    uint32_t w = (off - 0x80) / 4, sh = off % 4;
    top.p_cpu__we.set(true);
    top.p_cpu__waddr.set<uint32_t>(w);
    top.p_cpu__be.set<uint32_t>(((1u << bytes) - 1) << sh);
    top.p_cpu__wdata.set<uint32_t>(v << (8 * sh));
    tick();
    top.p_cpu__we.set(false);
}

static void ring_write(uint32_t off, unsigned bytes, uint32_t v) {
    uint32_t sh = off % 4;
    top.p_q__we.set(true);
    top.p_q__waddr.set<uint32_t>((off - RING) / 4);
    top.p_q__be.set<uint32_t>(((1u << bytes) - 1) << sh);
    top.p_q__wdata.set<uint32_t>(v << (8 * sh));
    tick();
    top.p_q__we.set(false);
}

// A CPU store at region offset `off`: the tap takes the block's 24 words, the ring is copied.
static void store(uint32_t off, unsigned bytes, uint32_t v) {
    for (unsigned k = 0; k < bytes; k++) {
        if (off + k < sizeof blk) blk[off + k] = uint8_t(v >> (8 * k));
        else mem[VIDEO + off + k] = uint8_t(v >> (8 * k));
    }
    if (off >= 0x80 && off < 0xE0) cpu_write(off, bytes, v);
    else if (off >= RING && off < RING + 4 * RING_WORDS) ring_write(off, bytes, v);
    else tick();
}

static uint32_t cpu_read(uint32_t word) {
    top.p_cpu__raddr.set<uint32_t>(word);
    top.step();
    return top.p_cpu__rdata.get<uint32_t>();
}

static uint32_t u16_at(uint32_t off) { return blk[off] | uint32_t(blk[off + 1]) << 8; }

// The next op's register stores, issued early while this one runs (random mode). Not the ring:
// it is memory, and the hash after this op would see it.
static bool early_store() {
    if (pc >= ops.size() || ops[pc].op[0] != 'w' || ops[pc].a >= sizeof blk) return false;  // memory: hashed at the run
    const Op &o = ops[pc++];
    store(uint32_t(o.a), unsigned(atoi(o.op.c_str() + 1) / 8), uint32_t(o.b));
    return true;
}

// The kick's word as bchisel.c builds it; false when the firmware refuses the QUEUE.
static bool kick_word(unsigned cmd, uint32_t &w) {
    w = cmd;
    if (cmd != QUEUE) return true;
    uint32_t start = u16_at(Q_START), count = u16_at(Q_COUNT);
    if (count == 0 || start + count > RING_WORDS) return false;
    w |= start << 8 | count << 17;
    return true;
}

static long run(unsigned cmd, bool early, std::string &err, bool &refused) {
    uint32_t w;
    refused = !kick_word(cmd, w);
    blk[0x80] = uint8_t(cmd);
    long t0 = now;
    if (refused) return 0;
    top.p_cpu__we.set(true);
    top.p_cpu__waddr.set<uint32_t>(0);
    top.p_cpu__be.set<uint32_t>(1);
    top.p_cpu__wdata.set<uint32_t>(w);
    tick();
    top.p_cpu__we.set(false);
    bool seen = false;
    while (now - t0 < 60000000) {
        bool b = top.p_busy.get<bool>();
        seen |= b;
        if (!b && (seen || now - t0 > 3)) break;
        if (!(early && b && !top.p_copying.get<bool>() && rnd(8) == 0 && early_store())) tick();
    }
    if ((cmd >= 1 && cmd <= 7) && !seen) err += " BUSY never rose;";
    if (top.p_busy.get<bool>()) err += " BUSY never fell;";
    return now - t0;
}

static void load(const char *path) {
    std::ifstream script(path);
    std::string line;
    while (std::getline(script, line)) {
        std::istringstream it(line.substr(0, line.find('#')));
        Op o{"", 0, 0};
        std::string ta, tb;
        if (!(it >> o.op)) continue;
        it >> ta >> tb;
        o.a = strtoull(ta.c_str(), nullptr, 0), o.b = strtoull(tb.c_str(), nullptr, 0);
        if (o.op == "dump") o.a = 0, o.op += " " + ta;
        ops.push_back(o);
    }
}

int main(int argc, char **argv) {
    if (argc < 3) return std::puts("usage: blitter_tb <script> <expected> [fast|random|deep [seed]] [out]"), 2;
    deep = argc > 3 && !strcmp(argv[3], "deep");
    randomize = deep || (argc > 3 && !strcmp(argv[3], "random"));
    lcg += argc > 4 ? strtoull(argv[4], nullptr, 0) : 0;
    std::ifstream expect(argv[2]);
    std::ofstream out(argc > 5 ? argv[5] : "/dev/null");
    load(argv[1]);
    top.p_rst.set(true);
    tick(); tick();
    top.p_rst.set(false);
    tick();
    std::string want;
    unsigned n = 0, fails = 0;
    while (pc < ops.size()) {
        const Op o = ops[pc++];
        if (o.op == "seed") seed(o.a);
        else if (o.op.rfind("dump ", 0) == 0) std::ofstream(o.op.substr(5), std::ios::binary).write((const char *)&mem[LO], HI - LO);
        else if (o.op[0] == 'w') store(uint32_t(o.a), unsigned(atoi(o.op.c_str() + 1) / 8), uint32_t(o.b));
        else if (o.op[0] == 'm')  // memory at a linear address (span lists, maps), as the CPU leaves it
            for (unsigned k = 0; k < unsigned(atoi(o.op.c_str() + 1) / 8); k++) mem[uint32_t(o.a) + k] = uint8_t(o.b >> (8 * k));
        else if (o.op == "run") {
            std::string err;
            bool refused;
            long clk = run(unsigned(o.a), randomize, err, refused);
            uint32_t cycles = refused ? 0 : cpu_read(24), status = cpu_read(0) >> 24;
            char got[128];
            snprintf(got, sizeof got, "R %u %u %u %016llx", n, cycles, status, (unsigned long long)hash());
            out << got << ' ' << clk << " cmd " << o.a << '\n';
            std::getline(expect, want);
            if (want != got || !err.empty() || bad) {
                std::printf("MISMATCH op %u (cmd %llu):\n  want %s\n  got  %s%s\n  bad accesses %ld\n", n, (unsigned long long)o.a,
                            want.c_str(), got, err.c_str(), bad);
                if (++fails >= 3) return 1;
            }
            n++;
        }
    }
    std::printf("blitter_tb: %u ops, %u mismatches\n", n, fails);
    return fails != 0;
}
