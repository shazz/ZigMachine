// Replay testbench for rtl/video/zm_video_comp.v against the wasm machine.
//
//   video_comp_tb [--timing LAT] <dump dir> <frame>...
//
// For each frame recorded by tools/video_dump.py it runs the compositor in the
// machine's order (video_replay.h) against a memory that stalls at random
// (video_mem.h), and checks two things: the PFB row every pass leaves in memory
// equals the machine's, and the picture the frame builds equals the browser's
// (f<N>.mix, tools/video_mix.py). `--timing LAT` serves memory as a port with
// LAT clocks of first-beat latency and a beat a clock, skips the per-pass
// read-back, and reports the clocks a pass, a line and a frame take.
// Exits non-zero on any difference.
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "zm_video_comp.cc"
#include "video_replay.h"

namespace {

using Top = cxxrtl_design::p_zm__video__comp;
using Rig = vd::Rig<Top>;

// Replays one frame and prints its verdict: 0 matched, 1 differed, 2 not loadable.
int run_frame(Rig& rig, vd::Replay<Rig>& r, const char* dir, const char* frame) {
    static vd::Frame f;
    f = vd::Frame{};
    if (!vd::load(dir, std::atol(frame), f)) {
        std::printf("FAIL cannot load frame %s from %s (with its .mix)\n", frame, dir);
        return 2;
    }
    r.f = &f;
    r.bad_pixels = r.bad_regs = r.bad_picture = r.max_pass = r.max_line = 0;
    rig.mem.bad = 0;
    r.run();
    r.check_picture();
    bool overflow = rig.top.p_overflow.get<bool>();
    bool ok = r.bad_pixels == 0 && r.bad_regs == 0 && r.bad_picture == 0 && rig.mem.bad == 0 && !overflow;
    std::printf("frame %s: planes %x vram_changed %d: %ld bad pixels, %ld bad picture pixels, %ld bad registers, "
                "%ld bad accesses, overflow %d, max %ld clocks/pass, %ld clocks/line, %ld clocks/frame -> %s\n",
                frame, f.planes, f.vram_changed, r.bad_pixels, r.bad_picture, r.bad_regs, rig.mem.bad,
                int(overflow), r.max_pass, r.max_line, r.frame_clocks, ok ? "MATCH" : "DIFFER");
    return ok ? 0 : 1;
}

}  // namespace

int main(int argc, char** argv) {
    int lat = -1, first_arg = 1;
    if (argc > 2 && !std::strcmp(argv[1], "--timing")) lat = std::atoi(argv[2]), first_arg = 3;
    if (argc < first_arg + 2) {
        std::fprintf(stderr, "usage: video_comp_tb [--timing LAT] <dump dir> <frame>...\n");
        return 2;
    }
    static Rig rig;  // the CXXRTL model is large: keep it off the stack
    rig.mem.fixed_lat = lat;
    rig.top.p_vbase.set<uint32_t>(0);
    rig.top.p_dbase.set<uint32_t>(vd::Mem::kFb0);
    rig.top.p_d__ok.set(true);
    static vd::Replay<Rig> r(rig);
    r.check_passes = lat < 0;
    int failed = 0;
    for (int i = first_arg + 1; i < argc; i++) {
        int verdict = run_frame(rig, r, argv[first_arg], argv[i]);
        if (verdict == 2) return 2;
        failed += verdict;
    }
    return failed ? 1 : 0;
}
