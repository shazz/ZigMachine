// CXXRTL testbench for rtl/board/hdmi_audio_core.v: the test pattern and tone
// through rtl/hdmi/zm_hdmi_tx.v, and the TMDS symbols parsed back by a reference
// sink (tests/tb/hdmi_decode.h) and packet checker (tests/tb/hdmi_packet_check.h).
// Over three frames it checks:
//   - every period, preamble, guard band, TERC4 symbol, packet and BCH ECC;
//   - every video pixel equals the pattern's, 12 clocks earlier, and the syncs
//     carried in control periods and islands equal the pattern's;
//   - one AVI and one Audio InfoFrame a frame, one ACR a CTS period (every
//     N / 128 samples), every CTS sent once and their average exact;
//   - every sample sent equals a from-scratch model of the tone (the 440/660 Hz
//     phase accumulators and the -12 dBFS sine), in order, none dropped or
//     repeated, at the sample rate on average, and no queue overflow.
// 48 kHz over 3 frames by default; tests/tb/hdmi_audio44_tb.cpp builds this at
// 44.1 kHz (HDMI_RATE44) over 12 frames. Built and run by tests/test_rtl.py;
// `HDMI_WAV=out.wav` also writes what the sink heard.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <fstream>
#include <memory>
#include "hdmi_packet_check.h"
#ifdef HDMI_RATE44
#include "hdmi_audio44.cc"
using Top = cxxrtl_design::p_hdmi__audio44;
constexpr unsigned FS = 44100, N_ACR = 6272, FRAMES = 12;
#else
#include "hdmi_audio_core.cc"
using Top = cxxrtl_design::p_hdmi__audio__core;
constexpr unsigned FS = 48000, N_ACR = 6144, FRAMES = 3;
#endif

static int failures = 0;
#define CHECK(cond, ...)                                     \
    do {                                                     \
        if (!(cond)) {                                       \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__); \
            std::printf(__VA_ARGS__);                        \
            std::printf("\n");                               \
            if (++failures > 20) std::exit(1);               \
        }                                                    \
    } while (0)

constexpr long FRAME = 1056L * 628L;
constexpr int LATENCY = 12;

// The tone, from its definition (rtl/board/hdmi_tone.v's header), not its code.
static int16_t tone(uint32_t phase) {
    const unsigned p = phase >> 24, i = (p & 64) ? 63 - (p & 63) : (p & 63);
    const int t = int(std::lround(8231.0 * std::sin(2.0 * M_PI * (i + 0.5) / 256.0)));
    return int16_t((p & 128) ? -t : t);
}

struct Src { bool de, hs, vs; unsigned rgb; };

static void write_wav(const char *path, const std::vector<std::pair<int16_t, int16_t>> &s) {
    std::ofstream f(path, std::ios::binary);
    auto u32 = [&](uint32_t v) { f.write(reinterpret_cast<const char *>(&v), 4); };
    auto u16 = [&](uint16_t v) { f.write(reinterpret_cast<const char *>(&v), 2); };
    f << "RIFF";
    u32(36 + 4 * s.size());
    f << "WAVEfmt ";
    u32(16), u16(1), u16(2), u32(FS), u32(FS * 4), u16(4), u16(16);
    f << "data";
    u32(4 * s.size());
    for (auto &x : s) u16(uint16_t(x.first)), u16(uint16_t(x.second));
}

struct Bench {
    std::unique_ptr<Top> top = std::make_unique<Top>();
    HdmiSink sink;
    PacketCheck pk;
    std::deque<Src> src;
    long src_samples = 0, video_px = 0, sync_px = 0, bad_px = 0, bad_sync = 0;

    void tick() {
        top->p_clk.set(false);
        top->step();
        top->p_clk.set(true);
        top->step();
    }
    Src source() {
        return {top->p_src__de.get<bool>(), top->p_src__hs.get<bool>(), top->p_src__vs.get<bool>(),
                top->p_src__r.get<unsigned>() << 16 | top->p_src__g.get<unsigned>() << 8 | top->p_src__b.get<unsigned>()};
    }
    // What the sink saw against what the pattern sent LATENCY clocks before.
    void compare(long t, const Src &s) {
        if ((s.de != sink.px.video || (s.de && s.rgb != sink.px.rgb)) && bad_px++ < 5)
            std::printf("  pixel %ld: video %d %06X, want %d %06X\n", t, sink.px.video, sink.px.rgb, s.de, s.rgb);
        video_px += s.de;
        if (!sink.px.syncs) return;
        sync_px++;
        if ((sink.px.hs != s.hs || sink.px.vs != s.vs) && bad_sync++ < 5) std::printf("  pixel %ld: syncs\n", t);
    }
    void run(long clocks) {
        for (long t = 0; t < clocks; t++) {
            tick();
            src.push_back(source());
            src_samples += top->p_src__valid.get<bool>();
            const uint32_t sym = top->p_sym.get<uint32_t>();
            const size_t npk = sink.packets.size();
            sink.step(sym & 0x3FF, sym >> 10 & 0x3FF, sym >> 20 & 0x3FF);
            for (size_t i = npk; i < sink.packets.size(); i++) pk.take(sink.packets[i]);
            if (src.size() <= LATENCY) continue;
            compare(t, src.front());
            src.pop_front();
        }
    }
    void check_stream() {
        for (auto &e : sink.errors) CHECK(false, "sink: %s", e.c_str());
        for (auto &e : pk.errors) CHECK(false, "packets: %s", e.c_str());
        CHECK(bad_px == 0, "%ld video pixels differ from the pattern (of %ld)", bad_px, video_px);
        CHECK(bad_sync == 0, "%ld pixels with the wrong syncs (of %ld)", bad_sync, sync_px);
        CHECK(video_px >= FRAMES * 800 * 600, "only %ld video pixels", video_px);
        // One of each a frame, plus one on the first island after reset (frame 0 starts there).
        CHECK(pk.avi == int(FRAMES) + 1 && pk.aif == int(FRAMES) + 1, "%d AVI and %d Audio InfoFrames in %u frames",
              pk.avi, pk.aif, FRAMES);
        // One ACR a CTS period: every N / 128 samples sent (the last may still be due).
        const long periods = src_samples / (N_ACR / 128);
        CHECK(pk.acr >= periods - 1 && pk.acr <= periods, "%d ACR packets for %ld CTS periods", pk.acr, periods);
        CHECK(!top->p_aud__overflow.get<bool>(), "the sample queue overflowed");
    }
    void check_audio(long clocks) {
        const long want = std::lround(clocks * double(FS) / 40e6);
        CHECK(std::labs(src_samples - want) <= 1, "%ld samples sent, want %ld (%u Hz)", src_samples, want, FS);
        CHECK(long(pk.samples.size()) >= src_samples - 4, "%zu samples received of %ld sent", pk.samples.size(),
              src_samples);
        long bad = 0;
        const uint32_t inc_l = uint32_t(std::lround(440.0 * 4294967296.0 / FS));
        const uint32_t inc_r = uint32_t(std::lround(660.0 * 4294967296.0 / FS));
        for (size_t n = 0; n < pk.samples.size(); n++) {
            const int16_t l = tone(uint32_t(n) * inc_l), r = tone(uint32_t(n) * inc_r);
            if ((pk.samples[n].first != l || pk.samples[n].second != r) && bad++ < 5)
                std::printf("  sample %zu: %d %d, want %d %d\n", n, pk.samples[n].first, pk.samples[n].second, l, r);
        }
        CHECK(bad == 0, "%ld samples differ from the tone", bad);
    }
};

int main() {
    Bench b;
    b.pk.fs = FS;
    b.pk.n_acr = N_ACR;
    b.top->p_rst.set(true);
    for (int i = 0; i < 4; i++) b.tick();
    b.top->p_rst.set(false);
    const long clocks = FRAMES * FRAME + 1056;
    b.run(clocks);
    b.check_stream();
    b.check_audio(clocks + 4);
    if (const char *wav = std::getenv("HDMI_WAV")) write_wav(wav, b.pk.samples);
    std::printf("hdmi_audio %u Hz: %zu packets (%d audio, %d ACR, %d AVI, %d AIF, %d null), %zu samples, %ld video "
                "pixels; CTS sum off the ideal by at most %.3f clocks\n",
                FS, b.sink.packets.size(), b.pk.asp, b.pk.acr, b.pk.avi, b.pk.aif, b.pk.null, b.pk.samples.size(),
                b.video_px, b.pk.cts_worst);
    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    return 0;
}
