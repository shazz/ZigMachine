// CXXRTL testbench for rtl/video/zm_tmds_shift.v, zm_dvi_out's 10:1 serialiser,
// behind the TMDS encoder (tests/tb/zm_tmds_ser_top.v). The pixel clock and the
// 5x clock are driven with aligned rising edges, as the PLL gives them; the
// ODDR is modelled as sending D1 (q[0]) then D2 (q[1]) each fast clock. The
// bits on the wire must be the encoder's symbols, one after another, bit 0
// first, two bits a fast clock and five fast clocks a symbol, with one fixed
// latency, whatever the phase of the shifter's free-running mod-5 counter
// against the pixel clock (all five are run). Built and run by tests/test_rtl.py.
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "zm_tmds_ser.cc"

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

uint32_t rng = 0x2468ACE1u;
uint32_t rnd() {
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}

using Top = cxxrtl_design::p_zm__tmds__ser;
const long kPixels = 20000;
const int kMaxLag = 60;  // bits: the encoder's two registers + the shifter's load

struct Trace {
    std::vector<unsigned> sym;  // the encoder's output, one per pixel clock
    std::vector<int> bits;      // the wire, in the order sent
};

// One fast clock; the pixel clock rises with it when `pix_edge`. After the edge
// the shifter's two bits are what the ODDR sends during the next fast period.
void fast_tick(Top& top, bool pix_edge, Trace& tr) {
    top.p_clk5.set(false);
    if (pix_edge) top.p_pix__clk.set(false);
    top.step();
    top.p_clk5.set(true);
    if (pix_edge) top.p_pix__clk.set(true);
    top.step();
    unsigned q = top.p_q.get<uint32_t>();
    tr.bits.push_back(q & 1);
    tr.bits.push_back((q >> 1) & 1);
    if (pix_edge) tr.sym.push_back(top.p_sym.get<uint32_t>());
}

// `skew` fast clocks before the first pixel edge set the mod-5 counter's phase.
Trace run(int skew) {
    Top top;
    Trace tr;
    for (int k = 0; k < skew; k++) fast_tick(top, false, tr);
    tr.bits.clear();
    for (long t = 0; t < kPixels; t++) {
        top.p_rst.set(t < 4);
        top.p_de.set((t % 1056) < 800);
        top.p_d.set<uint32_t>((rnd() & 3) == 0 ? (rnd() & 1 ? 0x00 : 0xFF) : rnd() & 0xFF);
        top.p_c.set<uint32_t>(rnd() & 3);
        for (int k = 0; k < 5; k++) fast_tick(top, k == 0, tr);
    }
    return tr;
}

// The latency in bits from symbol `first`'s edge to its bit 0 on the wire at
// which every later symbol matches, or -1 if no latency does.
int find_lag(const Trace& tr, long first) {
    for (int lag = 0; lag < kMaxLag; lag++) {
        bool ok = true;
        for (long n = first; ok && n < (long)tr.sym.size() - 8; n++) {
            for (int j = 0; ok && j < 10; j++) {
                long at = n * 10 + lag + j;
                ok = tr.bits[at] == (int)((tr.sym[n] >> j) & 1);
            }
        }
        if (ok) return lag;
    }
    return -1;
}

void check_phase(int skew) {
    Trace tr = run(skew);
    long data = 0;
    for (unsigned s : tr.sym) data += s != tr.sym[0];
    CHECK(data > kPixels / 2, "skew %d: the encoder sent only %ld distinct symbols", skew, data);
    const long first = 8;  // past the reset and the pipeline's start
    int lag = find_lag(tr, first);
    CHECK(lag >= 0, "skew %d: the wire is not the symbols, bit 0 first, at any latency", skew);
    if (lag < 0) return;
    CHECK(lag % 2 == 0, "skew %d: latency %d bits is not a whole fast clock", skew, lag);
    std::printf("zm_tmds_shift: skew %d, %zu symbols on the wire, latency %d bits\n", skew, tr.sym.size(), lag);
}

}  // namespace

int main() {
    for (int skew = 0; skew < 5; skew++) check_phase(skew);
    if (failures) std::printf("zm_tmds_shift: %d failure(s)\n", failures);
    return failures ? 1 : 0;
}
