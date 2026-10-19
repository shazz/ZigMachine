// Verilator harness for tests/dcache/ (tests/test_blit_dcache.py): the board's cart core
// (VexRiscv_I16w2D4SealFpu) on a memory model, plus a stand-in for CHISEL that writes a rect of
// RAM behind the core's D-cache, as zm_blit writes DDR over HP2. Usage: dcache_tb <elf> [store wait].
// The store wait (default 0) holds every data-bus write that many extra cycles, as a blocking DDR
// write on the board (~18 cycles a store, the ZIGGY bench): tests/blitpath/ times hwBlit with it.
// Device at 0xf0000000 (uncached: the core's IO range is address bit 31):
//   +0  w  exit code (ends the run)          +4  r  cycle counter
//   +8  w  REPORT line                       +12 w  "blit": the descriptor at this address,
//   +16 w  watch: the line to count reads of        {dst, stride, w, h, color} (u32 each)
//   +20 r  reads of the watched line since the watch was set
//   +24 rw a word for the program (tests/blitpath/: the video CSR VBASE)
//   +28 rw what CHISEL's window answers at its CYCLES word (0x91000060); the window reads 0 else
//   +32 r  data-bus writes so far
// Prints REPORT lines, then "EXIT <code> CYCLES <n>"; exits with the program's code (2 on a timeout).
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

#include "VVexRiscv.h"
#include "verilated.h"

namespace {

constexpr uint32_t kRam = 0x40000000, kRamSize = 4u << 20, kDev = 0xf0000000;
constexpr uint64_t kTimeout = 4000000;

std::vector<uint8_t> ram(kRamSize);
uint64_t cycle = 0, watched = 0, writes = 0;
uint32_t watch = 1;  // no line: lines are 32-byte aligned
uint32_t dev_word = 0, win_cycles = 0, store_wait = 0;
int exit_code = -1;

uint8_t* at(uint32_t a) { return a - kRam < kRamSize ? &ram[a - kRam] : nullptr; }

uint32_t word(uint32_t a) {
    uint32_t v = 0;
    if (uint8_t* p = at(a)) std::memcpy(&v, p, 4);
    return v;
}

bool load_elf(const char* path) {
    std::ifstream f(path, std::ios::binary);
    std::vector<uint8_t> e((std::istreambuf_iterator<char>(f)), {});
    if (e.size() < 52 || std::memcmp(e.data(), "\x7f" "ELF", 4) != 0) return false;
    uint32_t phoff, phnum = 0;
    std::memcpy(&phoff, &e[28], 4);
    std::memcpy(&phnum, &e[44], 2);
    for (uint32_t i = 0; i < phnum; i++) {
        const uint8_t* ph = &e[phoff + 32 * i];
        uint32_t type, off, paddr, filesz;
        std::memcpy(&type, ph, 4), std::memcpy(&off, ph + 4, 4);
        std::memcpy(&paddr, ph + 12, 4), std::memcpy(&filesz, ph + 16, 4);
        if (type != 1) continue;  // PT_LOAD
        for (uint32_t b = 0; b < filesz; b++)
            if (uint8_t* p = at(paddr + b)) *p = e[off + b];
    }
    return true;
}

void blit(uint32_t desc) {  // the rect, straight into RAM: the core's cache never sees it
    uint32_t dst = word(desc), stride = word(desc + 4), w = word(desc + 8), h = word(desc + 12);
    uint8_t color = (uint8_t)word(desc + 16);
    for (uint32_t j = 0; j < h; j++)
        for (uint32_t i = 0; i < w; i++)
            if (uint8_t* p = at(dst + j * stride + i)) *p = color;
}

uint32_t read(uint32_t a) {
    if (a == kDev + 4) return (uint32_t)cycle;
    if (a == kDev + 20) return (uint32_t)watched;
    if (a == kDev + 24) return dev_word;
    if (a == kDev + 28 || a == 0x91000060u) return win_cycles;
    if (a == kDev + 32) return (uint32_t)writes;
    if ((a & ~31u) == watch) watched++;
    return word(a);
}

void write(uint32_t a, uint32_t v, unsigned sel) {
    if (a == kDev) exit_code = (int)v;
    if (a == kDev + 8) std::printf("REPORT %u\n", v);
    if (a == kDev + 12) blit(v);
    if (a == kDev + 16) watch = v & ~31u, watched = 0;
    if (a == kDev + 24) dev_word = v;
    if (a == kDev + 28) win_cycles = v;
    uint8_t* p = at(a);
    for (int b = 0; p && b < 4; b++)
        if (sel >> b & 1) p[b] = (uint8_t)(v >> (8 * b));
}

// One Wishbone port: an access is acked the cycle after it shows up (a write `wait` cycles later).
template <typename Cyc, typename Stb, typename We, typename Adr, typename Sel, typename Mosi>
void port(bool& ack, uint32_t& miso, uint32_t& held, uint32_t wait, Cyc cyc, Stb stb, We we, Adr adr, Sel sel,
          Mosi mosi) {
    if (ack) {
        ack = false;
        return;
    }
    if (!(cyc && stb)) return;
    if (we && held++ < wait) return;
    held = 0;
    uint32_t a = (uint32_t)adr << 2;
    if (we) write(a, mosi, sel), writes++;
    else miso = read(a);
    ack = true;
}

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2 || !load_elf(argv[1])) return std::printf("usage: dcache_tb <elf> [store wait]\n"), 3;
    store_wait = argc > 2 ? (uint32_t)std::strtoul(argv[2], nullptr, 0) : 0;
    VVexRiscv cpu;
    cpu.externalResetVector = kRam;
    cpu.timerInterrupt = cpu.softwareInterrupt = cpu.externalInterruptArray = 0;
    bool iack = false, dack = false;
    uint32_t idat = 0, ddat = 0, iheld = 0, dheld = 0;
    for (; cycle < kTimeout && exit_code < 0; cycle++) {
        cpu.reset = cycle < 16;
        cpu.iBusWishbone_ACK = iack, cpu.iBusWishbone_DAT_MISO = idat, cpu.iBusWishbone_ERR = 0;
        cpu.dBusWishbone_ACK = dack, cpu.dBusWishbone_DAT_MISO = ddat, cpu.dBusWishbone_ERR = 0;
        cpu.clk = 0;
        cpu.eval();
        port(iack, idat, iheld, 0, cpu.iBusWishbone_CYC, cpu.iBusWishbone_STB, cpu.iBusWishbone_WE, cpu.iBusWishbone_ADR,
             cpu.iBusWishbone_SEL, cpu.iBusWishbone_DAT_MOSI);
        port(dack, ddat, dheld, store_wait, cpu.dBusWishbone_CYC, cpu.dBusWishbone_STB, cpu.dBusWishbone_WE, cpu.dBusWishbone_ADR,
             cpu.dBusWishbone_SEL, cpu.dBusWishbone_DAT_MOSI);
        cpu.clk = 1;
        cpu.eval();
    }
    std::printf("EXIT %d CYCLES %llu\n", exit_code, (unsigned long long)cycle);
    return exit_code < 0 ? 2 : exit_code;
}
