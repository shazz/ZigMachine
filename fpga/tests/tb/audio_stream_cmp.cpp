// Two sample streams (int16 L, R raw), compared as tests/tb/audio_compare.h does:
//   audio_stream_cmp <rtl.raw> <zig.raw> exact|near|ym
// `exact`: every sample equal (the PCM path, gains on the register grid); `near`: every
// sample within NEAR LSB (a player whose f32 gains are off the grid, VOL / 256 and PAN /
// 128: the MOD player's v / 64 / 1.4 and +-0.6, quantised by host/audio_regs.h); `ym`:
// the music must agree (jt49 and ym.zig are different models: spectra, partials,
// envelopes). Used by
// tools/audio_sim_compare.py on the board SoC sim's tap against the native host.
#include <cstdio>
#include <cstring>
#include "audio_compare.h"

constexpr int NEAR = 32;  // LSB: empirical (hybridglenz: worst 25); a wrong sample byte is off by hundreds

static long near(const Stereo &rtl, const Stereo &zig, size_t n, int &worst) {
    long bad = 0;
    worst = 0;
    for (size_t i = 0; i < n; i++) {
        const int d = std::max(std::abs(rtl[i].first - zig[i].first), std::abs(rtl[i].second - zig[i].second));
        worst = std::max(worst, d);
        bad += d > NEAR;
    }
    return bad;
}

int main(int argc, char **argv) {
    if (argc < 4) return std::printf("usage: audio_stream_cmp <rtl.raw> <zig.raw> exact|near|ym\n"), 2;
    const Stereo rtl = load_raw(argv[1]), zig = load_raw(argv[2]);
    const size_t n = std::min(rtl.size(), zig.size());
    if (!std::strcmp(argv[3], "near")) {
        int worst;
        const long bad = near(rtl, zig, n, worst);
        std::printf("stream: %zu samples, %ld off by more than %d LSB (worst %d)\n", n, bad, NEAR, worst);
        return bad || !n ? 1 : 0;
    }
    if (!std::strcmp(argv[3], "exact")) {
        const long bad = exact(rtl, zig);
        std::printf("stream: %zu samples, %ld differ\n", n, bad);
        return bad ? 1 : 0;
    }
    const YmStats st = ym(rtl, zig);
    std::printf("stream: %zu samples against the machine's YM\n", n);
    report(st);
    const bool ok = st.windows > 0 && st.pct(st.sim, 0.5) >= 0.9 && st.peaks_same * 10 >= st.windows * 9 &&
                    st.env_corr >= 0.9;
    return ok ? 0 : 1;
}
