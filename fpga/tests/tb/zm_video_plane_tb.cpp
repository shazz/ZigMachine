// CXXRTL testbench for rtl/video/zm_video_plane.v: the line geometry it hands
// the fetcher (address and length) against a reference model, over random
// planes, and WHEN it takes a pass. The address is pipelined four registers
// deep, so the inputs must have held four clocks before `start`: a start that
// comes sooner must wait until they have (and then fetch the right address),
// and a start after that must be taken at once (the clocks every real pass
// sees). Built and run by tests/test_rtl.py; exits non-zero on a failure.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include "zm_video_plane.cc"

static int failures = 0;
#define CHECK(cond, ...)                                     \
    do {                                                     \
        if (!(cond)) {                                       \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__); \
            std::printf(__VA_ARGS__);                        \
            std::printf("\n");                               \
            if (++failures > 10) std::exit(1);               \
        }                                                    \
    } while (0)

using Top = cxxrtl_design::p_zm__video__plane;
static long now = 0;     // ticks so far: outputs read after tick n are the edge ending cycle n
static long taken = -1;  // the cycle the last pass was taken in (`upd` the clock after)

static void tick(Top &t) {
    t.p_clk.set(false);
    t.step();
    t.p_clk.set(true);
    t.step();
    if (t.p_upd.get<bool>()) taken = now;
    now++;
}

static uint32_t rng = 12345;
static uint32_t rnd() { return rng = rng * 1664525u + 1013904223u; }

struct Plane {
    uint32_t base, mode, stride, py, hs_live, res, seed, hpos, seen, flicker;
};

enum { NORMAL = 0, FS = 1, SCROLL = 2, MED = 3, OVS = 4 };

static unsigned decode(const Plane &p) {
    return p.mode >= 1 && p.mode <= 4 ? p.mode : p.stride == 400 ? FS : NORMAL;
}

static uint32_t ref_addr(const Plane &p) {
    const unsigned m = decode(p);
    const bool phys = m == FS || m == OVS || (m == MED && p.stride >= 800);
    const uint32_t row = phys ? p.py : (p.py - 40) & 0x1FF;
    return p.base + row * p.stride + (m == SCROLL ? p.hs_live : 0);
}

static uint32_t ref_len(const Plane &p) {
    const unsigned m = decode(p);
    const bool ovm = p.stride >= 800, med_line = m == MED && p.res == 2;
    if (m == FS) return p.stride > 1021 ? 0x7FF : p.stride & 0x7FF;
    if (m == OVS) return 400;
    if (m == MED) return med_line ? (ovm ? 800 : 640) : (ovm ? 400 : 320);
    return 320;
}

static Plane random_plane() {
    static const uint32_t strides[] = {160, 320, 400, 640, 800, 1000, 1200};
    Plane p;
    p.base = rnd();
    p.mode = rnd() % 7;
    p.stride = rnd() % 4 ? strides[rnd() % 7] : rnd() & 0xFFFF;
    p.py = rnd() % 280;
    p.hs_live = rnd() & 0xFFFF;
    p.res = rnd() % 3;
    p.seed = rnd() & 0xFF;
    p.hpos = rnd() % 64;
    p.seen = rnd() & 3;
    p.flicker = rnd() & 3;
    return p;
}

static void apply(Top &t, const Plane &p) {
    t.p_base.set<uint32_t>(p.base);
    t.p_mode.set<uint32_t>(p.mode);
    t.p_stride.set<uint32_t>(p.stride);
    t.p_py.set<uint32_t>(p.py);
    t.p_hs__live.set<uint32_t>(p.hs_live);
    t.p_res.set<uint32_t>(p.res);
    t.p_seed.set<uint32_t>(p.seed);
    t.p_hpos.set<uint32_t>(p.hpos);
    t.p_hs.set<uint32_t>(p.hs_live);
    t.p_seen.set<uint32_t>(p.seen);
    t.p_flicker.set<uint32_t>(p.flicker);
}

// One pass: the inputs change in cycle c0, `start` comes `wait` cycles later;
// or (`lead` 1..3) other inputs land, `start` comes the next clock, and the
// pass's own inputs land `lead` - 1 clocks after that, while it waits. (Inputs
// that move in the very clock of a taken start are not its pass's: as before
// the pipeline, the pass takes what it computed from the clocks before.)
static void pass(Top &t, const Plane &p, int wait, int lead) {
    taken = -1;
    long s = now, c0 = now;
    if (lead > 0) {
        apply(t, random_plane());
        tick(t);
        s = now;
        t.p_start.set(true);
        for (int i = 0; i < lead; i++) {
            if (i == lead - 1) {
                apply(t, p);
                c0 = now;
            }
            tick(t);
            t.p_start.set(false);
        }
    } else {
        apply(t, p);
        c0 = now;
        for (int i = 0; i < wait; i++) tick(t);
        s = now;
        t.p_start.set(true);
        tick(t);
        t.p_start.set(false);
    }
    for (int i = 0; i < 16 && taken < 0; i++) tick(t);
    const long want = s > c0 + 4 ? s : c0 + 4;  // the first cycle the address is right
    CHECK(taken == want, "wait %d lead %d: pass taken %ld cycles after the inputs moved, want %ld", wait, lead,
          taken - c0, want - c0);
    CHECK(t.p_fetch__addr.get<uint32_t>() == ref_addr(p), "wait %d mode %u stride %u py %u: addr %08x, want %08x",
          wait, p.mode, p.stride, p.py, t.p_fetch__addr.get<uint32_t>(), ref_addr(p));
    CHECK(t.p_fetch__len.get<uint32_t>() == ref_len(p), "wait %d mode %u stride %u: len %u, want %u", wait, p.mode,
          p.stride, t.p_fetch__len.get<uint32_t>(), ref_len(p));
    // Run the pass out: the fetch and the paint answer a few clocks after they are asked.
    for (int i = 0; i < 200 && !t.p_done.get<bool>(); i++) {
        const bool fs = t.p_fetch__start.get<bool>(), ps = t.p_paint__start.get<bool>();
        t.p_fetch__done.set(false);
        t.p_paint__done.set(false);
        if (fs) { tick(t); tick(t); t.p_fetch__done.set(true); }
        if (ps) { tick(t); tick(t); t.p_paint__done.set(true); }
        tick(t);
    }
    t.p_fetch__done.set(false);
    t.p_paint__done.set(false);
    CHECK(t.p_done.get<bool>(), "wait %d: the pass never finished", wait);
    tick(t);
}

int main() {
    Top t;
    t.p_rst.set(true);
    tick(t);
    tick(t);
    t.p_rst.set(false);
    for (int n = 0; n < 3000; n++) {
        const Plane p = random_plane();
        const int wait = n % 4 == 0 ? 400 : 1 + rnd() % 7;  // a real pass, then the early starts
        pass(t, p, wait, n % 4 == 1 ? 1 + rnd() % 3 : 0);
    }
    if (failures) return 1;
    std::printf("zm_video_plane: 3000 passes, addresses and start timing ok\n");
    return 0;
}
