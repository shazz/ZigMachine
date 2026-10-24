// Where a pass's clocks go: tests/tb/video_comp_tb.cpp's replay, counting every clock of the
// frame by the pass FSM's phase (zm_video_pass.v), PAINT split into the plane line's fetch and
// the painter after it.
//
//   video_phase_tb [--timing LAT] [--fuse] [--line-major [--nopfb]] <dump dir> <frame>
//
// The memory is video_comp_tb's (`--timing LAT`: a beat a comp clock after LAT; the board's HP
// port gives at most a beat a SYS clock, 0.8 a comp clock, so the row I/O phases here are the
// RTL's floor and the board's row costs come from VCAL, cycles/vcal.c). Prints one line:
//   ZM PHASE passes N clocks C idle I load L fill F fetch X paint P mix M store S
// in comp clocks for the whole frame (BG passes included, LATCH/CLEAR/PRESENT in idle).
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "zm_video_comp.cc"
#include "video_replay.h"

namespace {

using Top = cxxrtl_design::p_zm__video__comp;
using Rig = vd::Rig<Top>;

enum { IDLE, LOAD, PAINT, MIX, STORE, FILL, FETCH, NPH };
long g_ph[NPH];

void sample(Top& t) {
    int st = int(t.p_u__pass_2e_st.get<uint32_t>());
    if (st == PAINT && t.p_u__pp_2e_u__fetch_2e_busy.get<bool>()) st = FETCH;
    g_ph[st < NPH ? st : IDLE]++;
}

}  // namespace

int main(int argc, char** argv) {
    int lat = 0, a = 1;
    bool fuse = false, lm = false, nopfb = false;
    for (; a < argc; a++) {
        if (!std::strcmp(argv[a], "--timing") && a + 1 < argc) lat = std::atoi(argv[++a]);
        else if (!std::strcmp(argv[a], "--fuse")) fuse = true;
        else if (!std::strcmp(argv[a], "--line-major")) lm = true;
        else if (!std::strcmp(argv[a], "--nopfb")) nopfb = true;
        else break;
    }
    if (argc != a + 2) {
        std::fprintf(stderr, "usage: video_phase_tb [--timing LAT] [--fuse] [--line-major [--nopfb]] <dir> <frame>\n");
        return 2;
    }
    static Rig rig;
    rig.mem.fixed_lat = lat;
    rig.top.p_vbase.set<uint32_t>(0);
    rig.top.p_dbase.set<uint32_t>(vd::Mem::kFb0);
    rig.top.p_d__ok.set(true);
    rig.after_cycle = [] { sample(rig.top); };
    static vd::Replay<Rig> r(rig);
    static vd::Frame f;
    if (!vd::load(argv[a], std::atol(argv[a + 1]), f)) return std::printf("FAIL cannot load %s\n", argv[a + 1]), 2;
    r.f = &f, r.check_passes = false, r.fuse = fuse, r.line_major = lm, r.nopfb = nopfb;
    r.run();
    std::printf("ZM PHASE planes %x fused %d clocks %ld idle %ld load %ld fill %ld fetch %ld paint %ld mix %ld store %ld\n",
                f.planes, int(r.fused), r.frame_clocks, g_ph[IDLE], g_ph[LOAD], g_ph[FILL], g_ph[FETCH], g_ph[PAINT],
                g_ph[MIX], g_ph[STORE]);
    return 0;
}
