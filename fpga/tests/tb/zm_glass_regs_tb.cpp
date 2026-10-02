// CXXRTL testbench for rtl/glass/zm_glass_regs.v: the ARM's AXI3 view of the
// console, driven as the PS's GP0 drives it (single beats, AW and W in any
// order, B and R back-pressured), and the cart CPU's side of the key FIFO.
// The register map comes from gen/glass_map.py through -D defines (tests/
// test_rtl_glass.py), so the testbench checks the map rather than restating it.
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "zm_glass_regs.cc"

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

#include "glass_axi.h"

static void reset() {
    idle();
    top.p_rst.set(true);
    tick();
    tick();
    top.p_rst.set(false);
    tick();
}

static void test_identity_and_reset() {
    CHECK(axi_read(REG_ID) == ID_VALUE, "ID");
    CHECK(axi_read(REG_VERSION) == VERSION, "VERSION");
    CHECK(axi_read(REG_CTRL) == 0 && !top.p_cpu__run.get<bool>(), "the cart CPU must start in reset");
    CHECK(axi_read(REG_LOAD_BASE) == DDR_CART_BASE, "LOAD_BASE resets to DDR_CART_BASE");
    CHECK(axi_read(REG_OSD_FG) == 0xFFFFFF, "OSD_FG resets to white");
    CHECK(axi_read(0x0FFC) == 0 && axi_read(0x2000) == 0, "unmapped reads 0");
}

static void test_write_orders() {
    unsigned v = 0x1234;
    for (int order = 0; order < 3; order++)
        for (int k = 0; k < 4; k++) {
            v = v * 2654435761u + 1;
            CHECK(axi_write(REG_SCRATCH, v, 0xF, order, 40 + k) == unsigned(40 + k), "BID not echoed");
            CHECK(axi_read(REG_SCRATCH) == v, "SCRATCH order %d", order);
        }
    axi_write(REG_SCRATCH, 0xAAAA5555, 0x0);
    CHECK(axi_read(REG_SCRATCH) == v, "a write with no byte enabled must be ignored");
    axi_write(REG_ID, 0);
    CHECK(axi_read(REG_ID) == ID_VALUE, "ID is read-only");
}

static void test_run_and_cart_reports() {
    top.p_cart__state__we.set(true);
    top.p_cart__state__in.set(CART_RUNNING);
    tick();
    idle();
    CHECK(axi_read(REG_CART_STATE) == 0, "a CPU in reset reports nothing");
    axi_write(REG_CTRL, CTRL_RUN | CTRL_OSD);
    CHECK(top.p_cpu__run.get<bool>() && top.p_osd__en.get<bool>(), "CTRL bits");
    CHECK(axi_read(REG_STATUS) & ST_RUNNING, "STATUS.RUNNING");
    top.p_cart__state__we.set(true);
    top.p_cart__state__in.set(CART_RUNNING);
    top.p_cart__beat__we.set(true);
    top.p_cart__beat__in.set(42);
    tick();
    idle();
    CHECK(axi_read(REG_CART_STATE) == CART_RUNNING && axi_read(REG_CART_BEAT) == 42, "cart reports");
    axi_write(REG_CTRL, 0);
    CHECK(axi_read(REG_CART_STATE) == 0 && axi_read(REG_CART_BEAT) == 0, "reset clears the reports");
}

static unsigned pop() {
    CHECK(top.p_key__valid.get<bool>(), "pop on an empty FIFO");
    unsigned v = top.p_key__data.get<unsigned>();
    top.p_key__pop.set(true);
    tick();
    top.p_key__pop.set(false);
    return v;
}

static void test_key_fifo() {
    for (unsigned i = 0; i < 3; i++) axi_write(REG_KEY_PUSH, KEY_DOWN | (0x41 + i));
    CHECK(axi_read(REG_KEY_LEVEL) == 3, "level 3");
    for (unsigned i = 0; i < 3; i++) CHECK(pop() == (KEY_DOWN | (0x41 + i)), "FIFO order");
    CHECK(!top.p_key__valid.get<bool>() && axi_read(REG_KEY_LEVEL) == 0, "empty again");
    for (unsigned i = 0; i < KEY_DEPTH + 1; i++) axi_write(REG_KEY_PUSH, i);
    unsigned st = axi_read(REG_STATUS);
    CHECK((st & ST_KEY_FULL) && (st & ST_KEY_OVERFLOW), "full + overflow, status 0x%x", st);
    CHECK(axi_read(REG_KEY_LEVEL) == KEY_DEPTH, "a push into a full FIFO is dropped");
    CHECK(pop() == 0, "the oldest event survives an overflow");
    axi_write(REG_CTRL, CTRL_KEY_FLUSH);
    st = axi_read(REG_STATUS);
    CHECK(axi_read(REG_KEY_LEVEL) == 0 && !(st & ST_KEY_OVERFLOW), "flush empties and clears");
    CHECK(axi_read(REG_CTRL) == 0, "KEY_FLUSH is a strobe, not stored");
}

static void test_osd_text() {
    std::vector<unsigned> seen;
    auto write_and_watch = [&](unsigned addr, unsigned data) {
        top.p_s__awvalid.set(true);
        top.p_s__awaddr.set(addr);
        top.p_s__wvalid.set(true);
        top.p_s__wdata.set(data);
        top.p_s__wstrb.set(0xF);
        top.p_s__bready.set(true);
        for (int i = 0; i < 4; i++) {
            tick();
            idle();
            if (top.p_osd__we.get<bool>())
                seen.push_back(top.p_osd__waddr.get<unsigned>() << 16 | top.p_osd__wdata.get<unsigned>());
        }
    };
    write_and_watch(OFF_OSD_TEXT + 4 * 37, OSD_INVERSE | 'Z');
    write_and_watch(OFF_OSD_TEXT + 4 * OSD_CHARS, 'X');
    CHECK(seen.size() == 1 && seen[0] == (37u << 16 | OSD_INVERSE | 'Z'), "OSD writes seen: %zu", seen.size());
}

int main() {
    reset();
    test_identity_and_reset();
    test_write_orders();
    test_run_and_cart_reports();
    test_key_fifo();
    test_osd_text();
    if (failures) return 1;
    std::printf("zm_glass_regs: ok\n");
    return 0;
}
