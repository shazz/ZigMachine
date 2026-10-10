// CXXRTL testbench for rtl/board/ym_test_audio.v (the dump player + the audio
// core, the ym-test bitstream's sound) against the Zig machine playing the same
// ROM (tests/audio_ref `rom`): the first seconds of the tune, compared as music
// (tests/tb/audio_compare.h: spectra, strongest partials, loudness envelopes),
// since jt49 and ym.zig are different models of the YM; the differences are
// reported. The player must also have walked the ROM (its word pointer moves),
// the YM is mono, and the core's status flags stay clear.
//   ym_audio_tb <zig.raw> [rtl.raw]
// Built with a 4 MHz system clock (tests/test_rtl_audio.py: SR 441 / 40000,
// YM 1 / 2): the same arithmetic as the board's 50 MHz, twelve times fewer clocks.
#include <cstdio>
#include <memory>
#include "ym_test_audio.cc"
#include "audio_compare.h"

using Top = cxxrtl_design::p_ym__test__audio;

struct Bench {
    std::unique_ptr<Top> top = std::make_unique<Top>();
    Stereo out;
    unsigned pc_max = 0;
    int failures = 0;

    void tick() {
        top->p_clk.set(false);
        top->step();
        top->p_clk.set(true);
        top->step();
        if (top->p_smp__valid.get<bool>())
            out.emplace_back(int16_t(top->p_smp__l.get<uint16_t>()), int16_t(top->p_smp__r.get<uint16_t>()));
        pc_max = std::max(pc_max, top->p_pc.get<unsigned>());
    }
    void check(bool ok, const char *what) {
        if (!ok) std::printf("FAIL: %s\n", what), failures++;
    }
    void checks(const Stereo &zig) {
        const YmStats st = ym(out, zig);
        std::printf("ym_test_audio: %zu samples (%.2f s), ROM words read %u\n", out.size(),
                    double(out.size()) / 44100, pc_max);
        report(st);
        check(top->p_status.get<unsigned>() == 0, "status flags set");
        check(pc_max > 100, "the player did not walk the ROM");
        check(st.windows * 4 >= long(out.size() / WIN) * 2 * 3, "too many silent windows");
        check(st.pct(st.sim, 0.5) >= 0.9, "median spectral similarity below 0.9");
        check(st.pct(st.sim, 0.1) >= 0.7, "10th-percentile spectral similarity below 0.7");
        check(st.peaks_same * 10 >= st.windows * 9, "the strongest partial differs in more than 10 % of windows");
        check(st.env_corr >= 0.9, "the loudness envelopes do not follow each other (tempo, timing)");
        bool mono = true;
        for (auto &s : out) mono = mono && s.first == s.second;
        check(mono, "the YM is mono: left != right");
    }
};

int main(int argc, char **argv) {
    if (argc < 2) return std::printf("usage: ym_audio_tb <zig.raw> [rtl.raw]\n"), 2;
    const Stereo zig = load_raw(argv[1]);
    Bench b;
    b.top->p_rst.set(true);
    for (int i = 0; i < 4; i++) b.tick();
    b.top->p_rst.set(false);
    while (b.out.size() < zig.size()) b.tick();
    if (argc > 2) save_raw(argv[2], b.out);
    b.checks(zig);
    if (b.failures) return std::printf("%d failure(s)\n", b.failures), 1;
    return 0;
}
