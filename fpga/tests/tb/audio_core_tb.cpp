// CXXRTL testbench for rtl/audio/zm_audio_core.v against the Zig machine: it
// plays a stimulus script (tests/tb/audio_script.h) into the core's registers,
// the PCM memory answering a clock after each request, and compares the
// samples with tests/audio_ref's for the same script.
//   audio_core_tb <script> <zig.raw> exact|ym|dump [rtl.raw]
// `exact`: every sample equal (the PCM path); `ym`: the music must agree
// (tests/tb/audio_compare.h) and the differences are reported; `dump`: only
// write rtl.raw, for tests/test_rtl_audio.py to judge. Also checked:
// the status flags stay clear, VERSION reads 0x00010200, and the YM registers
// read back what was written.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include "zm_audio_core.cc"
#include "audio_compare.h"
#include "audio_script.h"

using Top = cxxrtl_design::p_zm__audio__core;
static int failures = 0;
#define CHECK(cond, ...)                                                        \
    do {                                                                        \
        if (!(cond)) {                                                          \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__);                    \
            std::printf(__VA_ARGS__);                                           \
            std::printf("\n");                                                  \
            failures++;                                                         \
        }                                                                       \
    } while (0)

struct Bench {
    std::unique_ptr<Top> top = std::make_unique<Top>();
    const std::vector<uint8_t> *pcm = nullptr;
    Stereo out;
    uint8_t ym_written[16] = {};

    void tick() {
        // The memory: a byte a clock after it is asked for.
        const bool req = top->p_mem__req.get<bool>();
        const uint32_t a = top->p_mem__addr.get<uint32_t>();
        top->p_mem__ack.set(req);
        top->p_mem__data.set<uint8_t>(req && a < pcm->size() ? (*pcm)[a] : 0);
        top->p_clk.set(false);
        top->step();
        top->p_clk.set(true);
        top->step();
        top->step();  // CXXRTL's step stops at the commit: settle `ready` on the new state
        if (top->p_smp__valid.get<bool>())
            out.emplace_back(int16_t(top->p_smp__l.get<uint16_t>()), int16_t(top->p_smp__r.get<uint16_t>()));
    }
    void write(unsigned addr, uint32_t v) {
        while (!top->p_ready.get<bool>()) tick();
        top->p_wr.set(true);
        top->p_addr.set<uint16_t>(addr);
        top->p_wdata.set<uint32_t>(v);
        tick();
        top->p_wr.set(false);
        if (addr < 0x40) ym_written[addr / 4] = uint8_t(v);
        if (addr == 0x40 && (v & 1)) {  // machineAudioReset
            ym_written[7] = 0x3F;
            ym_written[8] = ym_written[9] = ym_written[10] = 0;
        }
    }
    uint32_t read(unsigned addr) {
        top->p_addr.set<uint16_t>(addr);
        top->step();
        return top->p_rdata.get<uint32_t>();
    }
    void play(const Script &s) {
        for (const Cmd &c : s.cmds) {
            if (c.mid) {  // into the next sample: at its first PCM fetch (if any), then its end
                const size_t n = out.size();
                while (!top->p_mem__req.get<bool>() && out.size() == n) tick();
                for (auto &w : c.wr) write(w.first, w.second);
                while (out.size() == n) tick();
                continue;
            }
            for (auto &w : c.wr) write(w.first, w.second);
            const size_t want = out.size() + size_t(c.run);
            while (out.size() < want) tick();
        }
    }
};

// The registers: status clear, VERSION, the YM registers read back.
static void check_registers(Bench &b) {
    CHECK(b.top->p_status.get<unsigned>() == 0, "status %x", b.top->p_status.get<unsigned>());
    CHECK(b.read(0x048) == 0x00010200, "VERSION %08x", b.read(0x048));
    for (unsigned r = 0; r < 16; r++)
        CHECK(b.read(4 * r) == b.ym_written[r], "YM R%u reads %u, written %u", r, b.read(4 * r), b.ym_written[r]);
}

static void compare(const Stereo &out, const Stereo &zig, const char *mode) {
    CHECK(out.size() == zig.size(), "%zu samples, the machine made %zu", out.size(), zig.size());
    if (!std::strcmp(mode, "exact")) {
        const long bad = exact(out, zig);
        CHECK(bad == 0, "%ld of %zu samples differ from the machine", bad, zig.size());
        std::printf("audio_core: %zu samples, %ld differ from the machine\n", out.size(), bad);
    } else if (!std::strcmp(mode, "ym")) {
        const YmStats st = ym(out, zig);
        std::printf("audio_core: %zu samples against the machine's YM\n", out.size());
        report(st);
        CHECK(st.windows > 0 && st.pct(st.sim, 0.5) >= 0.9, "the spectra differ");
        CHECK(st.peaks_same * 10 >= st.windows * 9, "the strongest partials differ");
        CHECK(st.env_corr >= 0.9, "the loudness envelopes differ");
    }
}

int main(int argc, char **argv) {
    if (argc < 4) return std::printf("usage: audio_core_tb <script> <zig.raw> exact|ym|dump [rtl.raw]\n"), 2;
    const Script script(argv[1]);
    const Stereo zig = load_raw(argv[2]);
    Bench b;
    b.pcm = &script.pcm;
    b.top->p_rst.set(true);
    for (int i = 0; i < 4; i++) b.tick();
    b.top->p_rst.set(false);
    b.play(script);
    if (argc > 4) save_raw(argv[4], b.out);
    check_registers(b);
    compare(b.out, zig, argv[3]);
    if (failures) return std::printf("%d failure(s)\n", failures), 1;
    return 0;
}
