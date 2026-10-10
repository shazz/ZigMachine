// CXXRTL testbench for rtl/audio/zm_audio_soc.v: the audio core behind its
// stamped write queue (zm_audio_sched), against the Zig machine. It plays the
// PCM stimulus script (tests/tb/audio_script.h) the way the board firmware does:
// every write stamped with the sample it lands before (the samples the script
// has run so far; a `mid` write lands after the sample being mixed, so the next
// one), pushed through QA/QD AHEAD of time while the core runs freely, the PCM
// memory answering a clock after each request.
//   audio_soc_tb <script> <zig.raw>
// Checks: every sample equal to the machine's; no write late, none dropped
// (STATUS), APPLIED = the writes pushed, every write landed at its stamp and
// between two mixes (watched on the core's port), ID reads 0x5A410100.
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <memory>
#include "zm_audio_soc.cc"
#include "audio_compare.h"
#include "audio_script.h"

using Top = cxxrtl_design::p_zm__audio__soc;
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

struct Write { uint32_t stamp, addr, data; };

struct Bench {
    std::unique_ptr<Top> top = std::make_unique<Top>();
    const std::vector<uint8_t> *pcm = nullptr;
    Stereo out;
    long off_stamp = 0;  // writes that landed at a sample other than their stamp
    std::deque<uint32_t> stamps;  // the stamps of the writes pushed, in order

    void tick() {
        const bool req = top->p_mem__req.get<bool>();
        const uint32_t a = top->p_mem__addr.get<uint32_t>();
        top->p_mem__ack.set(req);
        top->p_mem__data.set<uint8_t>(req && a < pcm->size() ? (*pcm)[a] : 0);
        if (top->p_core__wr.get<bool>()) {  // a write lands this clock: at its stamp?
            const uint32_t now = top->p_now.get<uint32_t>();
            if (stamps.empty() || stamps.front() != now) off_stamp++;
            if (!stamps.empty()) stamps.pop_front();
        }
        top->p_clk.set(false);
        top->step();
        top->p_clk.set(true);
        top->step();
        top->step();
        if (top->p_smp__valid.get<bool>())
            out.emplace_back(int16_t(top->p_smp__l.get<uint16_t>()), int16_t(top->p_smp__r.get<uint16_t>()));
    }
    void bus(unsigned word, uint32_t v) {
        top->p_bus__wr.set(true);
        top->p_bus__addr.set<uint8_t>(word);
        top->p_bus__wdata.set<uint32_t>(v);
        tick();
        top->p_bus__wr.set(false);
    }
    uint32_t read(unsigned word) {
        top->p_bus__addr.set<uint8_t>(word);
        top->step();
        return top->p_bus__rdata.get<uint32_t>();
    }
    void push(const Write &w) {
        bus(0, (w.stamp << 10) | (w.addr & 0x3FF));
        bus(1, w.data);
        stamps.push_back(w.stamp);
    }
};

// The script as stamped writes, and the samples it runs.
static long stamped(const Script &s, std::vector<Write> &ws) {
    long t = 0;
    for (const Cmd &c : s.cmds) {
        for (auto &w : c.wr) ws.push_back({uint32_t(t + (c.mid ? 1 : 0)), w.first, w.second});
        t += c.mid ? 1 : c.run;
    }
    return t;
}

int main(int argc, char **argv) {
    if (argc < 3) return std::printf("usage: audio_soc_tb <script> <zig.raw>\n"), 2;
    const Script script(argv[1]);
    const Stereo zig = load_raw(argv[2]);
    std::vector<Write> ws;
    const long total = stamped(script, ws);
    Bench b;
    b.pcm = &script.pcm;
    b.top->p_rst.set(true);
    for (int i = 0; i < 4; i++) b.tick();
    b.top->p_rst.set(false);
    // The firmware's way: keep the queue fed, a few hundred samples ahead of the sound.
    size_t next = 0;
    while (long(b.out.size()) < total) {
        const uint32_t now = b.read(2), level = b.read(3);
        if (next < ws.size() && level < 1000 && ws[next].stamp < now + 400) b.push(ws[next++]);
        else b.tick();
    }
    CHECK(next == ws.size(), "%zu of %zu writes pushed", next, ws.size());
    CHECK(b.read(7) == 0x5A410100, "ID %08x", b.read(7));
    CHECK((b.read(4) & 3) == 0, "STATUS %x: a write came late or was dropped", b.read(4));
    CHECK(b.read(6) == ws.size(), "APPLIED %u, pushed %zu", b.read(6), ws.size());
    CHECK(b.off_stamp == 0, "%ld writes landed off their stamp", b.off_stamp);
    const long bad = exact(b.out, zig);
    CHECK(long(b.out.size()) >= total && bad == 0, "%ld of %ld samples differ from the machine", bad, total);
    std::printf("audio_soc: %ld samples, %zu stamped writes, %ld differ from the machine\n", total, ws.size(), bad);
    if (failures) return std::printf("%d failure(s)\n", failures), 1;
    return 0;
}
