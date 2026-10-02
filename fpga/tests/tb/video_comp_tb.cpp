// Replay testbench for rtl/video/zm_video_comp.v against the wasm machine.
//
//   video_comp_tb [--timing] <dump dir> <frame>...
//
// For each frame recorded by tools/video_dump.py it runs the compositor line by
// line (video_replay.h) and checks two things: every pass of every line equals
// the machine's PFB row, and every finished line in the display buffer equals
// the browser's picture of that row (f<N>.mix, tools/video_mix.py), read
// through the display port in its own clock so the read costs the compositor
// nothing. `--timing` skips the per-pass line-buffer reads, so the mixer's
// sweeps overlap the next passes as they would on the board, and the busy
// clocks per line are the real ones. Exits non-zero on any difference.
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "zm_video_comp.cc"
#include "video_replay.h"

namespace {

using Top = cxxrtl_design::p_zm__video__comp;
using Rig = vd::Rig<Top>;

// Display buffer `buf` as 800 RGB pixels, clocking only the display port's domain.
void read_display(Top& top, int buf, uint8_t* rgb) {
    for (int x = 0; x < vd::ROW / 2; x++) {
        top.p_dp__raddr.set<uint32_t>(uint32_t(buf << 9 | x));
        top.p_dp__clk.set(true);
        top.step();
        top.p_dp__clk.set(false);
        top.step();
        uint64_t pair = top.p_dp__rdata.get<uint64_t>();
        for (int b = 0; b < 6; b++) rgb[x * 6 + b] = uint8_t(pair >> (8 * b));
    }
}

long check_display(Top& top, const vd::Frame& f, int y) {
    uint8_t rgb[vd::ROW * 3];
    read_display(top, y & 1, rgb);
    const uint8_t* want = &f.mix[size_t(y) * vd::ROW * 3];
    long bad = 0;
    for (int x = 0; x < vd::ROW; x++) {
        if (!std::memcmp(rgb + x * 3, want + x * 3, 3)) continue;
        if (++bad <= 5)
            std::printf("FAIL picture line %d x %d: rtl %02x%02x%02x browser %02x%02x%02x\n", y, x, rgb[x * 3],
                        rgb[x * 3 + 1], rgb[x * 3 + 2], want[x * 3], want[x * 3 + 1], want[x * 3 + 2]);
    }
    return bad;
}

// Replays one frame and prints its verdict: 0 matched, 1 differed, 2 not loadable.
int run_frame(Rig& rig, vd::Replay<Rig>& r, const char* dir, const char* frame) {
    static vd::Frame f;
    f = vd::Frame{};
    if (!vd::load(dir, std::atol(frame), f)) {
        std::printf("FAIL cannot load frame %s from %s (with its .mix)\n", frame, dir);
        return 2;
    }
    long bad_picture = 0;
    r.f = &f;
    r.on_line = [&](int y) { bad_picture += check_display(rig.top, f, y); };
    r.bad_pixels = r.bad_regs = r.max_line_cycles = r.max_line_busy = 0;
    r.run();
    bool hazard = rig.top.p_mix__hazard.get<bool>(), overflow = rig.top.p_overflow.get<bool>();
    bool ok = r.bad_pixels == 0 && r.bad_regs == 0 && bad_picture == 0 && rig.bad_reads == 0 && !overflow && !hazard;
    std::printf("frame %s: planes %x vram_changed %d: %ld bad pixels, %ld bad picture pixels, %ld bad registers, "
                "%ld bad reads, overflow %d, hazard %d, max %ld compose / %ld busy clocks/line -> %s\n",
                frame, f.planes, f.vram_changed, r.bad_pixels, bad_picture, r.bad_regs, rig.bad_reads, int(overflow),
                int(hazard), r.max_line_cycles, r.max_line_busy, ok ? "MATCH" : "DIFFER");
    return ok ? 0 : 1;
}

}  // namespace

int main(int argc, char** argv) {
    bool timing = argc > 1 && !std::strcmp(argv[1], "--timing");
    int first_arg = timing ? 2 : 1;
    if (argc < first_arg + 2) {
        std::fprintf(stderr, "usage: video_comp_tb [--timing] <dump dir> <frame>...\n");
        return 2;
    }
    static Rig rig;  // the CXXRTL model is large: keep it off the stack
    rig.set_clock = [](bool v) { rig.top.p_clk.set(v), rig.top.p_dp__clk.set(v); };
    rig.top.p_dp__free.set<uint32_t>(3);  // no scanout here: both display buffers are always free
    static vd::Replay<Rig> r(rig);
    r.check_passes = !timing;
    int failed = 0;
    for (int i = first_arg + 1; i < argc; i++) {
        int verdict = run_frame(rig, r, argv[first_arg], argv[i]);
        if (verdict == 2) return 2;
        failed += verdict;
    }
    return failed ? 1 : 0;
}
