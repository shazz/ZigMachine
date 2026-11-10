// CXXRTL testbench for ASTROLABE's mailbox (SPIKE): rtl/glass/zm_astro_mbox.v behind the glass
// block (zm_glass_regs.v), as tests/tb/zm_astro_top.v wires them. Both sides: the ARM over GP0
// (glass_axi.h's AXI3 master) and ZIGGY over Wishbone. The map (OFF_ASTRO, ASTRO_WORDS) comes
// from gen/glass_map.py through -D defines.
#include <cstdio>
#include <cstdlib>

#include "zm_astro_top.cc"

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

#define GLASS_AXI_TOP p_zm__astro__top
#include "glass_axi.h"

static void wb_idle() {
    top.p_wb__cyc.set(false);
    top.p_wb__stb.set(false);
    top.p_wb__we.set(false);
}

static void reset() {
    idle();
    wb_idle();
    top.p_rst.set(true);
    tick();
    tick();
    top.p_rst.set(false);
    tick();
}

// One Wishbone access: the strobe, the ack exactly one clock later, the word read then.
static unsigned wb(unsigned word, bool we, unsigned data = 0, unsigned sel = 0xF) {
    top.p_wb__cyc.set(true);
    top.p_wb__stb.set(true);
    top.p_wb__we.set(we);
    top.p_wb__adr.set(word);
    top.p_wb__dat__w.set(data);
    top.p_wb__sel.set(sel);
    top.step();
    CHECK(!top.p_wb__ack.get<bool>(), "ack before the clock");
    tick();
    CHECK(top.p_wb__ack.get<bool>(), "no ack the clock after the strobe (word %u)", word);
    unsigned v = top.p_wb__dat__r.get<unsigned>();
    wb_idle();
    tick();
    CHECK(!top.p_wb__ack.get<bool>(), "ack held");
    return v;
}

static unsigned pattern(unsigned i) { return i * 2654435761u ^ 0xA5A50000u; }

static void test_arm_writes_ziggy_reads_every_word() {
    for (unsigned i = 0; i < ASTRO_WORDS; i++) axi_write(OFF_ASTRO + 4 * i, pattern(i), 0xF, i % 3, i & 0xFFF);
    for (unsigned i = 0; i < ASTRO_WORDS; i++) CHECK(wb(i, false) == pattern(i), "word %u: ZIGGY reads what the ARM wrote", i);
}

static void test_ziggy_writes_arm_reads_with_byte_lanes() {
    wb(5, true, 0x11223344);
    wb(5, true, 0xAABBCCDD, 0x5); // bytes 0 and 2 only
    CHECK(axi_read(OFF_ASTRO + 4 * 5) == 0x11BB33DD, "byte lanes: got %08x", axi_read(OFF_ASTRO + 4 * 5));
    wb(1023, true, 0xCAFEF00D);
    CHECK(axi_read(OFF_ASTRO + 4 * 1023) == 0xCAFEF00D, "the last word");
    axi_write(OFF_ASTRO + 4 * 6, 0xFFFFFFFF, 0x2); // the ARM's byte lanes too
    CHECK(wb(6, false) == (pattern(6) | 0x0000FF00u), "ARM byte lane 1");
}

static void test_registers_and_page_do_not_alias() {
    axi_write(REG_SCRATCH, 0x5C5C5C5C);
    axi_write(OFF_ASTRO + REG_SCRATCH, 0x0A0A0A0A);
    CHECK(axi_read(REG_SCRATCH) == 0x5C5C5C5C, "SCRATCH kept");
    CHECK(wb(REG_SCRATCH / 4, false) == 0x0A0A0A0A, "the mailbox word at the same offset");
    CHECK(axi_read(REG_ID) == ID_VALUE, "registers still answer");
    CHECK(axi_read(OFF_ASTRO + 0x1000) == 0, "the page after the mailbox reads 0");
    unsigned w0 = wb(0, false);
    axi_write(OFF_OSD_TEXT, 0x41);
    axi_write(OFF_ASTRO + 0x1000, 0x42);
    CHECK(wb(0, false) == w0, "OSD text and the page after the mailbox never reach it");
}

// A mailbox write in the clock a mailbox read wants the RAM: the write takes the port, the read
// waits, and returns its own word (not the written one, not a stale one).
static void test_read_meets_write() {
    wb(10, true, 0x10101010);
    wb(11, true, 0x11111111);
    top.p_s__arvalid.set(true);
    top.p_s__araddr.set(OFF_ASTRO + 4 * 10);
    top.p_s__arid.set(9);
    top.p_s__rready.set(true);
    tick(); // AR taken: the read wants the RAM in the next clock, when the write comes
    top.p_s__arvalid.set(false);
    top.p_s__araddr.set(0x0BEC);
    top.p_s__awvalid.set(true);
    top.p_s__awaddr.set(OFF_ASTRO + 4 * 11);
    top.p_s__wvalid.set(true);
    top.p_s__wdata.set(0x22222222);
    top.p_s__wstrb.set(0xF);
    top.p_s__bready.set(true);
    tick(); // AW and W taken, the write done in that clock
    top.p_s__awvalid.set(false);
    top.p_s__wvalid.set(false);
    unsigned got = 0;
    for (int guard = 0; guard < 6 && !top.p_s__rvalid.get<bool>(); guard++) tick();
    CHECK(top.p_s__rvalid.get<bool>(), "R never came");
    got = top.p_s__rdata.get<unsigned>();
    tick();
    idle();
    tick();
    CHECK(got == 0x10101010, "a read beside a write: got %08x", got);
    CHECK(wb(11, false) == 0x22222222, "...and the write landed");
}

// ZIGGY reads a word in the clock the ARM writes it: the old word, whole (READ_FIRST).
static void test_ziggy_read_during_arm_write() {
    wb(20, true, 0x0D0D0D0D);
    top.p_s__awvalid.set(true);
    top.p_s__awaddr.set(OFF_ASTRO + 4 * 20);
    top.p_s__wvalid.set(true);
    top.p_s__wdata.set(0xE0E0E0E0);
    top.p_s__wstrb.set(0xF);
    top.p_s__bready.set(true);
    top.p_wb__cyc.set(true);
    top.p_wb__stb.set(true);
    top.p_wb__we.set(false);
    top.p_wb__adr.set(20);
    tick();
    unsigned v = top.p_wb__dat__r.get<unsigned>();
    idle();
    wb_idle();
    tick();
    tick();
    CHECK(v == 0x0D0D0D0D || v == 0xE0E0E0E0, "a torn word: %08x", v);
    CHECK(wb(20, false) == 0xE0E0E0E0, "the write landed");
}

// The ack is one clock: a strobe held past it is a new access, acked again a clock later.
static void test_ack_is_one_clock() {
    top.p_wb__cyc.set(true);
    top.p_wb__stb.set(true);
    top.p_wb__we.set(false);
    top.p_wb__adr.set(3);
    tick();
    CHECK(top.p_wb__ack.get<bool>(), "ack");
    tick();
    CHECK(!top.p_wb__ack.get<bool>(), "the ack held a second clock under a held strobe");
    tick();
    CHECK(top.p_wb__ack.get<bool>(), "the next access is acked");
    wb_idle();
    tick();
}

int main() {
    reset();
    test_arm_writes_ziggy_reads_every_word();
    test_ziggy_writes_arm_reads_with_byte_lanes();
    test_registers_and_page_do_not_alias();
    test_read_meets_write();
    test_ziggy_read_during_arm_write();
    test_ack_is_one_clock();
    if (failures) return 1;
    std::printf("zm_astro: OK\n");
    return 0;
}
