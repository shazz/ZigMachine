// CXXRTL testbench for the primitive self-test (rtl/board/prim_test/prim_test_core.v),
// driven over its GP0 slave as U-Boot drives it on the board.
//   prim_test_tb [BROKEN]   BROKEN: the lane built with BREAK_TEST (its reference
//                           has bit 0 inverted), or -1 for none
// Checks: the ID; every lane done and PASS, except BROKEN, which must FAIL with
// its first error at the first compare and bad bit 0 only; then (unbroken) a
// restart (CTRL bit0) that clears and re-runs everything with a new seed, and
// LOOP (CTRL bit1), whose runs accumulate. Prints the lane table it read.
#include <cstdio>
#include <cstdlib>

#include "prim_test_core.cc"

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

static cxxrtl_design::p_prim__test__core top;
static const unsigned LANE_BASE = 0x800, NWORDS = 8;

static void tick() {
    top.p_clk.set(false);
    top.step();
    top.p_clk.set(true);
    top.step();
}

static void axi_write(unsigned addr, unsigned data) {
    top.p_s__awvalid.set(true);
    top.p_s__awaddr.set(addr);
    top.p_s__awid.set(5u);
    top.p_s__wvalid.set(true);
    top.p_s__wdata.set(data);
    top.p_s__wstrb.set(0xFu);
    top.p_s__bready.set(true);
    bool aw = false, w = false;
    for (int guard = 0; !(aw && w); guard++) {
        CHECK(guard < 10, "write 0x%x not accepted", addr);
        if (guard >= 10) return;
        top.step();
        aw |= top.p_s__awready.get<bool>();
        w |= top.p_s__wready.get<bool>();
        tick();
        top.p_s__awvalid.set(!aw);
        top.p_s__wvalid.set(!w);
    }
    for (int guard = 0; !top.p_s__bvalid.get<bool>(); guard++) {
        CHECK(guard < 10, "no B for 0x%x", addr);
        if (guard >= 10) return;
        tick();
    }
    CHECK(top.p_s__bid.get<unsigned>() == 5u, "BID %u", top.p_s__bid.get<unsigned>());
    tick();
}

static unsigned axi_read(unsigned addr) {
    top.p_s__arvalid.set(true);
    top.p_s__araddr.set(addr);
    top.p_s__arid.set(9u);
    top.p_s__rready.set(true);
    top.step();
    CHECK(top.p_s__arready.get<bool>(), "AR not ready for 0x%x", addr);
    tick();
    top.p_s__arvalid.set(false);
    for (int guard = 0; !top.p_s__rvalid.get<bool>(); guard++) {
        CHECK(guard < 10, "no R for 0x%x", addr);
        if (guard >= 10) return 0;
        tick();
    }
    CHECK(top.p_s__rid.get<unsigned>() == 9u, "RID %u", top.p_s__rid.get<unsigned>());
    unsigned v = top.p_s__rdata.get<unsigned>();
    tick();
    return v;
}

static unsigned long long mask64(unsigned lo_addr) {
    return axi_read(lo_addr) | (unsigned long long)axi_read(lo_addr + 4) << 32;
}

// Run until no run is in progress (CTRL.BUSY = 0) and every lane is done.
static void wait_done(int nl) {
    unsigned long long all = nl == 64 ? ~0ull : (1ull << nl) - 1;
    for (long cycles = 0;; cycles += 4096) {
        CHECK(cycles < 4000000, "lanes still running after %ld clocks: done 0x%llx", cycles, mask64(0x010));
        if (cycles >= 4000000) std::exit(1);
        for (int i = 0; i < 4096; i++) tick();
        if (!(axi_read(0x004) & 1) && mask64(0x010) == all) return;
    }
}

struct Lane { unsigned w[NWORDS]; };

static Lane read_lane(int i) {
    Lane l;
    for (unsigned k = 0; k < NWORDS; k++) l.w[k] = axi_read(LANE_BASE + 32 * i + 4 * k);
    return l;
}

// The table, and the lanes against what is expected of them.
static void check_lanes(int nl, int broken) {
    unsigned long long pass = mask64(0x008);
    std::printf("lane status     errors   first_idx first_got bad[31:0] bad[63:32] bad[95:64] checks\n");
    for (int i = 0; i < nl; i++) {
        Lane l = read_lane(i);
        std::printf("%4d %08x %8u %08x  %08x  %08x  %08x   %08x   %u\n", i, l.w[0], l.w[1], l.w[2], l.w[3],
                    l.w[4], l.w[5], l.w[6], l.w[7]);
        bool lane_pass = l.w[0] >> 30 & 1;
        CHECK((l.w[0] >> 31) && (l.w[0] & 0xFF) == (unsigned)i, "lane %d status %08x", i, l.w[0]);
        CHECK(lane_pass == (bool)(pass >> i & 1), "lane %d: STATUS and PASS disagree", i);
        CHECK(l.w[7] > 0, "lane %d made no compares", i);
        if (i != broken) {
            CHECK(lane_pass && l.w[1] == 0 && l.w[2] == 0xFFFFFFFFu, "lane %d failed: %u errors", i, l.w[1]);
        } else {
            CHECK(!lane_pass && l.w[1] > 0, "broken lane %d passed", i);
            CHECK((l.w[2] & 0xFFFFu) == 0, "broken lane %d: first error at %08x, not the first compare", i, l.w[2]);
            CHECK(l.w[4] == 1 && l.w[5] == 0 && l.w[6] == 0, "broken lane %d: bad bits %08x %08x %08x", i,
                  l.w[4], l.w[5], l.w[6]);
        }
    }
}

static void check_restart_and_loop(int nl) {
    unsigned seed0 = axi_read(0x020), checks0 = read_lane(0).w[7];
    axi_write(0x004, 1);
    CHECK(axi_read(0x004) & 1, "restart did not start a run");
    CHECK(read_lane(0).w[7] < checks0, "restart did not clear the results");
    wait_done(nl);
    CHECK(axi_read(0x01C) == 1, "runs %u after a restart, not 1", axi_read(0x01C));
    CHECK(axi_read(0x020) != seed0, "restart kept the seed");
    check_lanes(nl, -1);
    axi_write(0x004, 3);  // restart, looping
    for (int i = 0; i < 200000 && axi_read(0x01C) < 3; i++)
        for (int k = 0; k < 64; k++) tick();
    axi_write(0x004, 0);  // stop looping; the run in progress ends
    wait_done(nl);
    CHECK(axi_read(0x01C) >= 3, "LOOP ran %u times", axi_read(0x01C));
    CHECK(read_lane(0).w[7] >= 3 * checks0, "LOOP did not accumulate: %u checks", read_lane(0).w[7]);
    check_lanes(nl, -1);
}

int main(int argc, char **argv) {
    int broken = argc > 1 ? std::atoi(argv[1]) : -1;
    top.p_rst.set(true);
    for (int i = 0; i < 4; i++) tick();
    top.p_rst.set(false);
    CHECK(axi_read(0x000) == 0x5052494Du, "ID %08x", axi_read(0x000));
    int nl = (int)axi_read(0x018);
    CHECK(nl > 0 && nl <= 64, "lane count %d", nl);
    wait_done(nl);
    check_lanes(nl, broken);
    if (broken < 0 && failures == 0) check_restart_and_loop(nl);
    std::printf("%s: %d lanes, %d failures\n", failures ? "FAIL" : "PASS", nl, failures);
    return failures ? 1 : 0;
}
