// CXXRTL testbench for rtl/video/zm_vtiming.v: runs two whole frames and checks
// the VESA 800x600@60 timing and the ZigMachine raster mapped inside it.
// Built and run by tests/test_rtl.py; exits non-zero on the first failure.
#include <cstdio>
#include <cstdlib>
#include "zm_vtiming.cc"

static int failures = 0;
#define CHECK(cond, ...)                                  \
    do {                                                  \
        if (!(cond)) {                                    \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__); \
            std::printf(__VA_ARGS__);                     \
            std::printf("\n");                            \
            if (++failures > 10) std::exit(1);            \
        }                                                 \
    } while (0)

struct Counts {
    long de = 0, active = 0, hsync_rise = 0, vsync_lines = 0;
    int hbl = 0, vbl = 0, next_hbl_line = 0;
};

static void tick(cxxrtl_design::p_zm__vtiming &top) {
    top.p_clk.set(false);
    top.step();
    top.p_clk.set(true);
    top.step();
}

// One clock's worth of checks; `prev_hsync` detects rising edges.
static void observe(cxxrtl_design::p_zm__vtiming &top, Counts &c, bool &prev_hsync, int &pending_hbl) {
    const unsigned x = top.p_out__x.get<unsigned>(), y = top.p_out__y.get<unsigned>();
    const bool hs = top.p_hsync.get<bool>();
    c.de += top.p_de.get<bool>();
    if (hs && !prev_hsync) c.hsync_rise++;
    prev_hsync = hs;
    if (x == 0 && top.p_vsync.get<bool>()) c.vsync_lines++;
    if (top.p_zm__hbl.get<bool>()) {
        const int line = top.p_zm__hbl__line.get<int>();
        CHECK(x == 800, "HBL at x=%u, want the first blank clock (800)", x);
        CHECK(line == c.next_hbl_line, "HBL announced line %d, want %d", line, c.next_hbl_line);
        c.next_hbl_line++;
        c.hbl++;
        pending_hbl = line;
    }
    if (top.p_zm__active.get<bool>()) {
        const int line = top.p_zm__line.get<int>();
        c.active++;
        CHECK(top.p_zm__x.get<unsigned>() == x, "raster x %u != output x %u", top.p_zm__x.get<unsigned>(), x);
        CHECK(line == int((y - 20) / 2), "raster line %d at output y %u", line, y);
        if (x == 0 && (y - 20) % 2 == 0) CHECK(pending_hbl == line, "line %d drawn without its HBL", line);
    }
    if (top.p_zm__vbl.get<bool>()) {
        CHECK(x == 0 && y == 580, "VBL at (%u, %u), want (0, 580)", x, y);
        c.vbl++;
    }
}

int main() {
    cxxrtl_design::p_zm__vtiming top;
    top.p_rst.set(true);
    tick(top);
    top.p_rst.set(false);
    const long frame = 1056L * 628L;
    for (int f = 0; f < 2; f++) {
        Counts c;
        bool prev_hsync = top.p_hsync.get<bool>();
        int pending_hbl = -1;
        for (long i = 0; i < frame; i++) {
            tick(top);
            observe(top, c, prev_hsync, pending_hbl);
        }
        CHECK(c.de == 800L * 600L, "frame %d: de clocks %ld", f, c.de);
        CHECK(c.active == 800L * 560L, "frame %d: raster clocks %ld", f, c.active);
        CHECK(c.hsync_rise == 628, "frame %d: hsync pulses %ld", f, c.hsync_rise);
        CHECK(c.vsync_lines == 4, "frame %d: vsync lines %ld", f, c.vsync_lines);
        CHECK(c.hbl == 280, "frame %d: HBL strobes %d", f, c.hbl);
        CHECK(c.vbl == 1, "frame %d: VBL strobes %d", f, c.vbl);
    }
    std::printf(failures ? "zm_vtiming: %d failure(s)\n" : "zm_vtiming: 2 frames OK\n", failures);
    return failures ? 1 : 0;
}
