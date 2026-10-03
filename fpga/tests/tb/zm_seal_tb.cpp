// CXXRTL testbench for rtl/seal/zm_seal.v: the cart CPU's bus windows.
//
// The window bases and sizes come from rtl/seal/zm_seal_map.vh as -D's (the map
// is the definition); the POLICY is restated here, as the spec:
//   U: code --X, rodata R--, data/linear/video RW-, anything else ---
//   M: rw everywhere, x everywhere except the windows U can write.
// Checked: the map's own invariants, every window's edges, the regions the cart
// must never reach, and two million random addresses against the reference.
// Built and run by tests/test_rtl_seal.py; exits non-zero on failure.
#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "zm_seal.cc"

namespace {

int failures = 0;
#define CHECK(cond, ...)                       \
    do {                                       \
        if (!(cond)) {                         \
            std::printf("FAIL: " __VA_ARGS__); \
            std::printf("\n");                 \
            if (++failures > 20) std::exit(1); \
        }                                      \
    } while (0)

struct Window {
    const char* name;
    uint32_t base;
    unsigned log2;
    bool r, w, x;  // what U may do
};

const Window kWindows[] = {
    {"code", ZS_CODE_BASE, ZS_CODE_LOG2, false, false, true},
    {"rodata", ZS_RODATA_BASE, ZS_RODATA_LOG2, true, false, false},
    {"data", ZS_DATA_BASE, ZS_DATA_LOG2, true, true, false},
    {"linear", ZS_LINEAR_BASE, ZS_LINEAR_LOG2, true, true, false},
    {"video", ZS_VIDEO_BASE, ZS_VIDEO_LOG2, true, true, false},
};
const Window kFirmware = {"firmware", ZS_FW_BASE, ZS_FW_LOG2, false, false, false};

bool in(const Window& w, uint32_t a) { return (uint64_t)a - w.base < (1ull << w.log2); }

struct Perm {
    bool r, w, x;
};

Perm reference(uint32_t a, bool user) {
    for (const Window& w : kWindows)
        if (in(w, a)) return user ? Perm{w.r, w.w, w.x} : Perm{true, true, !w.w};
    return user ? Perm{false, false, false} : Perm{true, true, true};
}

cxxrtl_design::p_zm__seal top;

Perm rtl(uint32_t a, bool user) {
    top.p_addr.set<uint32_t>(a);
    top.p_user.set<bool>(user);
    top.step();
    return {top.p_r.get<bool>(), top.p_w.get<bool>(), top.p_x.get<bool>()};
}

void compare(uint32_t a, const char* why) {
    for (int user = 0; user < 2; user++) {
        Perm got = rtl(a, user), want = reference(a, user);
        CHECK(got.r == want.r && got.w == want.w && got.x == want.x,
              "%s 0x%08x %s: rtl rwx=%d%d%d, spec %d%d%d", why, a, user ? "U" : "M", got.r, got.w, got.x, want.r,
              want.w, want.x);
    }
}

void check_map() {
    const Window* all[] = {&kWindows[0], &kWindows[1], &kWindows[2], &kWindows[3], &kWindows[4], &kFirmware};
    for (const Window* w : all) {
        CHECK(w->log2 >= 12 && w->log2 < 32, "%s: size 2^%u", w->name, w->log2);
        CHECK((w->base & ((1u << w->log2) - 1)) == 0, "%s: 0x%08x not aligned to its size", w->name, w->base);
        for (const Window* v : all)
            if (v != w) CHECK(!in(*v, w->base) && !in(*w, v->base), "%s overlaps %s", w->name, v->name);
        CHECK(!(w->w && w->x), "%s is both writable and executable for U", w->name);
    }
}

void check_edges() {
    for (const Window& w : kWindows) {
        uint32_t end = w.base + (1u << w.log2);
        uint32_t points[] = {w.base, w.base + 4, end - 4, end - 1, w.base - 1, w.base - 4, end, end + 4};
        for (uint32_t a : points) compare(a, w.name);
        Perm inside = rtl(w.base, true);
        CHECK(inside.r == w.r && inside.w == w.w && inside.x == w.x, "%s base: U rwx %d%d%d", w.name, inside.r,
              inside.w, inside.x);
    }
}

// What the seal exists for (REVIEW_FABLE.md #2): none of it is reachable from U.
void check_forbidden() {
    const uint32_t forbidden[] = {
        0x00000000,        // the boot ROM
        0x10000000,        // the SoC's SRAM
        ZS_FW_BASE,        // the firmware: sequencer state, mem_base copy, its stack
        ZS_FW_BASE + 0x7ffffc,
        0x42000000,        // past the cart's 32 MiB of DDR: Linux's, if the HP path maps it
        0x3ffffffc,        // just below main_ram
        0x80000000,        // the IO region's first byte
        0x90800000,        // just past the video window
        0xf0000000,        // the CSR bus: UART, video cmd/mem_base, the glass
        0xf0001800,
        0xfffffffc,
    };
    for (uint32_t a : forbidden) {
        Perm p = rtl(a, true);
        CHECK(!p.r && !p.w && !p.x, "U reaches 0x%08x: rwx=%d%d%d", a, p.r, p.w, p.x);
        Perm m = rtl(a, false);
        CHECK(m.r && m.w, "M cannot reach 0x%08x", a);
    }
}

void check_random() {
    uint64_t s = 0x2545f4914f6cdd1dull;
    for (int i = 0; i < 2000000; i++) {
        s ^= s << 13, s ^= s >> 7, s ^= s << 17;
        uint32_t a = (uint32_t)s;
        if (i & 1) {  // half of them near a window, where the bugs live
            const Window& w = kWindows[(s >> 40) % 5];
            a = w.base + (uint32_t)((int32_t)(a % (3u << w.log2)) - (int32_t)(1u << w.log2));
        }
        compare(a, "random");
        if (failures) return;
    }
}

}  // namespace

int main() {
    check_map();
    check_edges();
    check_forbidden();
    check_random();
    if (failures) return 1;
    std::printf("zm_seal: map, edges, forbidden regions and 2M random addresses OK\n");
    return 0;
}
