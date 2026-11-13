// Verilator harness for tests/test_ziggy_reads.py: tests/zigread_top.py's `zigread` (the cart core,
// WishboneHP, the HP slices and the sim DDR, which loads zm_ddr.init from the run directory).
// The core's IO space (byte address bit 31) is this device, acknowledged the cycle after a request:
//   0xf0000000 w exit code (ends the run)   0xf0000004 r cycle counter   0xf0000008 w REPORT word
// Prints REPORT lines, then "EXIT <code> CYCLES <n>"; exits with the program's code (2 on a timeout).
#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "Vzigread.h"
#include "verilated.h"
#if VM_TRACE
#include "verilated_vcd_c.h"  // built with --trace: ZM_TRACE=<first cycle>,<cycles> dumps zigread.vcd
#endif

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const char* lim = std::getenv("ZM_TB_CYCLES");
    const uint64_t timeout = lim ? std::strtoull(lim, nullptr, 0) : 50000000;
    Vzigread top;
    uint64_t cycle = 0;
    int exit_code = -1;
    bool ack = false;
    uint32_t miso = 0;
#if VM_TRACE
    Verilated::traceEverOn(true);
    VerilatedVcdC vcd;
    uint64_t t0 = 0, tn = 0;
    if (const char* t = std::getenv("ZM_TRACE")) std::sscanf(t, "%lu,%lu", &t0, &tn);
    if (tn) top.trace(&vcd, 99), vcd.open("zigread.vcd");
#endif
    for (; cycle < timeout && exit_code < 0; cycle++) {
        top.sys_rst = cycle < 16;
        top.dev_ack = ack, top.dev_dat_r = miso, top.dev_err = 0;
        top.sys_clk = 0;
        top.eval();
        bool req = top.dev_cyc && top.dev_stb && !ack;
        ack = false;
        if (req) {
            uint32_t a = (uint32_t)top.dev_adr << 2;
            if (top.dev_we) {
                if (a == 0xf0000000u) exit_code = (int)top.dev_dat_w;
                if (a == 0xf0000008u) std::printf("REPORT %u\n", top.dev_dat_w);
            } else {
                miso = a == 0xf0000004u ? (uint32_t)cycle : 0;
            }
            ack = true;
        }
        top.sys_clk = 1;
        top.eval();
#if VM_TRACE
        if (tn && cycle >= t0 && cycle < t0 + tn) vcd.dump(2 * cycle), vcd.dump(2 * cycle + 1);
#endif
    }
    std::printf("EXIT %d CYCLES %llu\n", exit_code, (unsigned long long)cycle);
    return exit_code < 0 ? 2 : exit_code;
}
