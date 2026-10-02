// CXXRTL testbench for rtl/video/zm_tmds_enc.v, against a software TMDS
// encoder written from the DVI 1.0 spec's flowchart (section 3.3.3), plus
// invariants that hold whatever the encoder: every data symbol decodes back to
// its byte, every blanking symbol is its control token, and the running
// disparity of the bits actually sent stays bounded through every data period.
// Built and run by tests/test_rtl.py; exits non-zero on the first failures.
#include <cstdio>
#include <cstdlib>

#include "zm_tmds_enc.cc"

namespace {

int failures = 0;
#define CHECK(cond, ...)                         \
    do {                                         \
        if (!(cond)) {                           \
            std::printf("FAIL: " __VA_ARGS__);   \
            std::printf("\n");                   \
            if (++failures > 10) std::exit(1);   \
        }                                        \
    } while (0)

int ones(unsigned v, int bits) {
    int n = 0;
    for (int i = 0; i < bits; i++) n += (v >> i) & 1;
    return n;
}

const unsigned kTokens[4] = {0x354, 0x0AB, 0x154, 0x2AB};  // C1C0 = 00, 01, 10, 11

// The spec's encoder, step by step, with its own disparity counter.
struct Reference {
    int cnt = 0;
    unsigned encode(bool de, unsigned d, unsigned c) {
        if (!de) {
            cnt = 0;
            return kTokens[c];
        }
        int n1 = ones(d, 8);
        bool use_xnor = n1 > 4 || (n1 == 4 && !(d & 1));
        unsigned qm = d & 1;
        for (int i = 1; i < 8; i++) {
            unsigned bit = ((qm >> (i - 1)) ^ (d >> i)) & 1;
            qm |= (use_xnor ? !bit : bit) << i;
        }
        qm |= unsigned(!use_xnor) << 8;
        int q1 = ones(qm, 8), q0 = 8 - q1, m8 = (qm >> 8) & 1;
        if (cnt == 0 || q1 == q0) {
            cnt += m8 ? q1 - q0 : q0 - q1;
            return unsigned(!m8) << 9 | qm & 0x100 | (m8 ? qm & 0xFF : ~qm & 0xFF);
        }
        if ((cnt > 0 && q1 > q0) || (cnt < 0 && q0 > q1)) {
            cnt += 2 * m8 + q0 - q1;
            return 0x200 | (qm & 0x100) | (~qm & 0xFF);
        }
        cnt += -2 * !m8 + q1 - q0;
        return qm & 0x1FF;
    }
};

// A decoder, as a DVI sink has it: undo the inversion, then the chaining.
unsigned decode(unsigned q) {
    unsigned d = (q & 0x200) ? ~q & 0xFF : q & 0xFF, out = d & 1;
    for (int i = 1; i < 8; i++) {
        unsigned bit = ((d >> i) ^ (d >> (i - 1))) & 1;
        out |= ((q & 0x100) ? bit : !bit) << i;
    }
    return out;
}

uint32_t rng = 0x12345678u;
uint32_t rnd() {
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}

}  // namespace

int main() {
    cxxrtl_design::p_zm__tmds__enc top;
    auto tick = [&] {
        top.p_clk.set(false);
        top.step();
        top.p_clk.set(true);
        top.step();
    };
    top.p_rst.set(true);
    tick();
    top.p_rst.set(false);
    Reference ref;
    struct In { bool de; unsigned d, c; } pipe[2] = {};
    long disparity = 0, worst = 0;
    const long kSymbols = 2000000;
    for (long t = 0; t < kSymbols; t++) {
        // Data periods of random length, the bytes biased toward the extremes.
        bool de = (t % 1056) < 800 && (t / 1056) % 7 != 6;
        unsigned d = (rnd() & 3) == 0 ? (rnd() & 1 ? 0x00 : 0xFF) : rnd() & 0xFF, c = rnd() & 3;
        top.p_de.set(de);
        top.p_d.set<uint32_t>(d);
        top.p_c.set<uint32_t>(c);
        tick();
        pipe[1] = pipe[0], pipe[0] = In{de, d, c};
        if (t < 1) continue;
        // Two registers: the input set before edge t is sent after edge t + 1.
        const In& in = pipe[1];
        unsigned q = top.p_q.get<uint32_t>(), want = ref.encode(in.de, in.d, in.c);
        CHECK(q == want, "symbol %ld: rtl %03x, spec %03x (de %d d %02x c %u)", t, q, want, in.de, in.d, in.c);
        if (!in.de) {
            CHECK(q == kTokens[in.c], "symbol %ld: blanking sent %03x for control %u", t, q, in.c);
            disparity = 0;
            continue;
        }
        CHECK(decode(q) == in.d, "symbol %ld: %03x decodes to %02x, sent %02x", t, q, decode(q), in.d);
        disparity += 2 * ones(q, 10) - 10;
        if (std::labs(disparity) > worst) worst = std::labs(disparity);
        CHECK(disparity == ref.cnt, "symbol %ld: wire disparity %ld, the encoder's count %d", t, disparity, ref.cnt);
    }
    CHECK(worst <= 10, "running disparity reached %ld", worst);
    if (failures) std::printf("zm_tmds_enc: %d failure(s)\n", failures);
    else std::printf("zm_tmds_enc: %ld symbols OK, worst disparity %ld\n", kSymbols, worst);
    return failures ? 1 : 0;
}
