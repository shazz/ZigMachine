// CXXRTL testbench for rtl/board/ym_test_core.v, the ym-test bitstream minus
// its clocks: the system side at 50 MHz and the pixel side at 40 MHz, as on the
// board (two clocks, edges on a 2.5 ns grid), the TMDS symbols parsed back by
// the reference sink (tests/tb/hdmi_decode.h) and packet checker
// (tests/tb/hdmi_packet_check.h, at 44.1 kHz: N 6272, every CTS sent once, the
// running CTS sum within a clock of the ideal). Over four frames it checks:
//   - every sample the sink hears is the system side's, in order from the
//     first: nothing dropped, repeated or reordered across the clock crossing;
//   - as many as 44.1 kHz gives (less the FIFO's prefill of 8);
//   - no FIFO overflow or underflow, no island queue overflow, core status clear;
//   - the sink's own checks (periods, guard bands, ECC, InfoFrames).
#include <cstdio>
#include <memory>
#include "ym_test_core.cc"
#include "hdmi_packet_check.h"
#include "audio_compare.h"

using Top = cxxrtl_design::p_ym__test__core;
constexpr long FRAME = 1056L * 628L;

struct Bench {
    std::unique_ptr<Top> top = std::make_unique<Top>();
    HdmiSink sink;
    PacketCheck pk;
    Stereo src;
    long pix_clocks = 0;
    bool sys = false, pix = false;
    int failures = 0;

    void check(bool ok, const char *what) {
        if (!ok) std::printf("FAIL: %s\n", what), failures++;
    }
    void sink_pixel() {
        pix_clocks++;
        const uint32_t sym = top->p_sym.get<uint32_t>();
        const size_t npk = sink.packets.size();
        sink.step(sym & 0x3FF, sym >> 10 & 0x3FF, sym >> 20 & 0x3FF);
        for (size_t i = npk; i < sink.packets.size(); i++) pk.take(sink.packets[i]);
    }
    // One 2.5 ns step: the system clock's period is 8 of them, the pixel clock's 10.
    void unit(long t, bool rst) {
        const bool s = t % 8 < 4, p = t % 10 < 5;
        top->p_sys__rst.set(rst);
        top->p_pix__rst.set(rst);
        if (s == sys && p == pix) return;
        top->p_sys__clk.set(s);
        top->p_pix__clk.set(p);
        top->step();
        if (s && !sys && top->p_src__valid.get<bool>())
            src.emplace_back(int16_t(top->p_src__l.get<uint16_t>()), int16_t(top->p_src__r.get<uint16_t>()));
        if (p && !pix && !rst) sink_pixel();
        sys = s, pix = p;
    }
    void checks() {
        for (auto &e : sink.errors) std::printf("  sink: %s\n", e.c_str());
        for (auto &e : pk.errors) std::printf("  packets: %s\n", e.c_str());
        check(sink.errors.empty() && pk.errors.empty(), "the HDMI stream has errors");
        const Stereo &got = pk.samples;
        long bad = 0, loud = 0;
        for (size_t i = 0; i < got.size(); i++) bad += i >= src.size() || got[i] != src[i];
        for (auto &s : got) loud += s.first != 0;
        check(bad == 0, "the samples heard are not the samples made, in order");
        const long want = long(double(pix_clocks) * 44100.0 / 40e6) - 8;
        check(std::labs(long(got.size()) - want) <= 4, "not 44.1 kHz");
        check(top->p_fault.get<unsigned>() == 0, "FIFO or island queue fault");
        check(top->p_status.get<unsigned>() == 0, "audio core status");
        check(loud >= 1000, "the tune is silent");  // Drooling opens with three notes, then a rest
        std::printf("ym_test: %zu samples heard of %zu made, %ld differ; %d ACR (CTS sum off by at most %.3f), "
                    "%d AVI, %d audio packets\n",
                    got.size(), src.size(), bad, pk.acr, pk.cts_worst, pk.avi, pk.asp);
    }
};

int main() {
    Bench b;
    b.pk.fs = 44100, b.pk.n_acr = 6272;
    long t = 0;
    for (; t < 400; t++) b.unit(t, true);
    while (b.pix_clocks < 4 * FRAME) b.unit(t++, false);
    b.checks();
    if (b.failures) return std::printf("%d failure(s)\n", b.failures), 1;
    return 0;
}
