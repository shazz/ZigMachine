// Comparing the RTL's samples with the Zig machine's (tests/audio_ref):
//   - exact(): sample for sample, the PCM path's contract;
//   - ym():    for the YM, where jt49 and machine/audio/ym.zig are different
//     models of the chip (DAC curves, a cycle-exact chip box-filtered vs a
//     point-sampled float model), what must still agree: the music. Over
//     4096-sample windows (Hann, mean removed) of the left channel it measures
//     the spectra's cosine similarity, whether the strongest partial lands in
//     the same FFT bin (10.8 Hz), and the loudness ratio; and over 50 Hz frames
//     (882 samples) how well the two loudness envelopes correlate (the notes
//     start and stop together: tempo, timing); plus the plain sample difference,
//     reported, not judged.
#pragma once
#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <string>
#include <utility>
#include <vector>

using Stereo = std::vector<std::pair<int16_t, int16_t>>;

inline Stereo load_raw(const std::string &path) {
    std::ifstream f(path, std::ios::binary);
    Stereo s;
    int16_t v[2];
    while (f.read(reinterpret_cast<char *>(v), 4)) s.emplace_back(v[0], v[1]);
    return s;
}

inline void save_raw(const char *path, const Stereo &s) {
    std::ofstream f(path, std::ios::binary);
    for (auto &x : s) f.write(reinterpret_cast<const char *>(&x.first), 2), f.write(reinterpret_cast<const char *>(&x.second), 2);
}

// The first difference and how many there are, over the shorter of the two.
inline long exact(const Stereo &rtl, const Stereo &zig) {
    long bad = 0;
    for (size_t i = 0; i < std::min(rtl.size(), zig.size()); i++) {
        if (rtl[i] == zig[i]) continue;
        if (bad++ < 5)
            std::printf("  sample %zu: rtl %d %d, zig %d %d\n", i, rtl[i].first, rtl[i].second, zig[i].first,
                        zig[i].second);
    }
    return bad;
}

inline void fft(std::vector<std::complex<double>> &a) {
    const size_t n = a.size();
    for (size_t i = 1, j = 0; i < n; i++) {
        size_t bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) std::swap(a[i], a[j]);
    }
    for (size_t len = 2; len <= n; len <<= 1) {
        const std::complex<double> w = std::polar(1.0, -2 * M_PI / double(len));
        for (size_t i = 0; i < n; i += len) {
            std::complex<double> u(1);
            for (size_t k = 0; k < len / 2; k++, u *= w) {
                const auto x = a[i + k], y = a[i + k + len / 2] * u;
                a[i + k] = x + y, a[i + k + len / 2] = x - y;
            }
        }
    }
}

struct YmStats {
    std::vector<double> sim, level_db;
    long windows = 0, peaks_same = 0, max_diff = 0;
    double env_corr = 0;  // Pearson, of the per-frame AC RMS
    double dc_rtl = 0, dc_zig = 0;
    double pct(std::vector<double> v, double p) const {
        if (v.empty()) return 0;
        std::sort(v.begin(), v.end());
        return v[size_t(p * double(v.size() - 1))];
    }
};

constexpr size_t WIN = 4096;

// The window's spectrum (bins 0..WIN/2) and its RMS, mean removed.
inline std::vector<double> spectrum(const Stereo &s, size_t at, double &rms) {
    double mean = 0, sq = 0;
    for (size_t i = 0; i < WIN; i++) mean += s[at + i].first;
    mean /= WIN;
    std::vector<std::complex<double>> a(WIN);
    for (size_t i = 0; i < WIN; i++) {
        const double x = s[at + i].first - mean;
        sq += x * x;
        a[i] = x * (0.5 - 0.5 * std::cos(2 * M_PI * double(i) / WIN));
    }
    rms = std::sqrt(sq / WIN);
    fft(a);
    std::vector<double> m(WIN / 2);
    for (size_t k = 0; k < WIN / 2; k++) m[k] = std::abs(a[k]);
    return m;
}

// One channel's AC RMS over each frame.
inline std::vector<double> frame_rms(const Stereo &a, size_t n, size_t frame) {
    std::vector<double> x;
    for (size_t at = 0; at + frame <= n; at += frame) {
        double m = 0, v = 0;
        for (size_t i = at; i < at + frame; i++) m += a[i].first;
        m /= double(frame);
        for (size_t i = at; i < at + frame; i++) v += (a[i].first - m) * (a[i].first - m);
        x.push_back(std::sqrt(v / double(frame)));
    }
    return x;
}

// Pearson correlation of the two signals' per-frame AC RMS.
inline double envelope_corr(const Stereo &a, const Stereo &b, size_t n, size_t frame = 882) {
    const auto x = frame_rms(a, n, frame), y = frame_rms(b, n, frame);
    double mx = 0, my = 0, sxy = 0, sxx = 0, syy = 0;
    for (size_t i = 0; i < x.size(); i++) mx += x[i], my += y[i];
    mx /= double(x.size()), my /= double(y.size());
    for (size_t i = 0; i < x.size(); i++)
        sxy += (x[i] - mx) * (y[i] - my), sxx += (x[i] - mx) * (x[i] - mx), syy += (y[i] - my) * (y[i] - my);
    return sxy / std::sqrt(sxx * syy + 1e-30);
}

inline YmStats ym(const Stereo &rtl, const Stereo &zig) {
    YmStats st;
    const size_t n = std::min(rtl.size(), zig.size());
    st.env_corr = envelope_corr(rtl, zig, n);
    for (size_t i = 0; i < n; i++) {
        st.max_diff = std::max(st.max_diff, long(std::abs(rtl[i].first - zig[i].first)));
        st.dc_rtl += rtl[i].first, st.dc_zig += zig[i].first;
    }
    st.dc_rtl /= double(n), st.dc_zig /= double(n);
    for (size_t at = 0; at + WIN <= n; at += WIN / 2) {
        double ra, za;
        const auto a = spectrum(rtl, at, ra), b = spectrum(zig, at, za);
        if (ra < 30 && za < 30) continue;  // both silent
        double ab = 0, aa = 0, bb = 0;
        for (size_t k = 2; k < a.size(); k++) ab += a[k] * b[k], aa += a[k] * a[k], bb += b[k] * b[k];
        st.sim.push_back(ab / std::sqrt(aa * bb + 1e-30));
        const auto pa = std::max_element(a.begin() + 2, a.end()) - a.begin();
        const auto pb = std::max_element(b.begin() + 2, b.end()) - b.begin();
        st.peaks_same += std::labs(long(pa - pb)) <= 1;
        st.level_db.push_back(20 * std::log10((ra + 1e-9) / (za + 1e-9)));
        st.windows++;
    }
    return st;
}

inline void report(const YmStats &s) {
    std::printf("  %ld windows: spectral similarity median %.3f, 10th percentile %.3f; strongest partial in the same "
                "bin %.1f %%; loudness envelopes correlate %.3f\n  level rtl/zig median %+.2f dB (10th..90th %+.2f..%+.2f); max sample difference %ld; "
                "mean rtl %.0f zig %.0f\n",
                s.windows, s.pct(s.sim, 0.5), s.pct(s.sim, 0.1), 100.0 * double(s.peaks_same) / double(s.windows),
                s.env_corr,
                s.pct(s.level_db, 0.5), s.pct(s.level_db, 0.1), s.pct(s.level_db, 0.9), s.max_diff, s.dc_rtl,
                s.dc_zig);
}
