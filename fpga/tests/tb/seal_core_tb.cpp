// Verilator harness for the sealed VexRiscv (vexgen `:seal`) running
// tests/seal/seal.S: both Wishbone buses answered from a memory model, plus the
// test device. Usage: seal_core_tb <elf>. Prints REPORT lines, then
// "EXIT <code> GUARD <n> CYCLES <n>"; exits non-zero on a test failure, a GUARD
// access or an unmapped one (U reached the bus where it must not), or a
// timeout.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

#include "VVexRiscv.h"
#include "verilated.h"

namespace {

constexpr uint32_t kRam = 0x40000000, kRamSize = 32u << 20;
constexpr uint32_t kVideo = 0x90000000, kVideoSize = 64u << 10;
constexpr uint32_t kDev = 0xf0000000, kGuard = 0xf0000010;
constexpr uint64_t kTimeout = 2000000;

std::vector<uint8_t> ram(kRamSize), video(kVideoSize);
uint64_t cycle = 0, guard = 0, unmapped = 0;
int exit_code = -1;

uint8_t* at(uint32_t a) {
    if (a - kRam < kRamSize) return &ram[a - kRam];
    if (a - kVideo < kVideoSize) return &video[a - kVideo];
    return nullptr;
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
        for (uint32_t b = 0; b < filesz; b++) *at(paddr + b) = e[off + b];
    }
    return true;
}

uint32_t read(uint32_t a) {
    if (a == kGuard) guard++;
    if (a == kDev + 4) return (uint32_t)cycle;
    uint8_t* p = at(a);
    if (!p) return unmapped++, 0xdeadbeef;
    uint32_t v;
    std::memcpy(&v, p, 4);
    return v;
}

void write(uint32_t a, uint32_t v, unsigned sel) {
    if (a == kGuard) guard++;
    if (a == kDev) exit_code = (int)v;
    if (a == kDev + 8) std::printf("REPORT 0x%08x %u\n", v, v);
    uint8_t* p = at(a);
    if (!p) {
        if (a < kDev) unmapped++;
        return;
    }
    for (int b = 0; b < 4; b++)
        if (sel >> b & 1) p[b] = (uint8_t)(v >> (8 * b));
}

// One Wishbone port: an access is acked the cycle after it shows up.
template <typename Cyc, typename Stb, typename We, typename Adr, typename Sel, typename Mosi>
void port(bool& ack, uint32_t& miso, Cyc cyc, Stb stb, We we, Adr adr, Sel sel, Mosi mosi) {
    if (ack) {
        ack = false;
        return;
    }
    if (!(cyc && stb)) return;
    uint32_t a = (uint32_t)adr << 2;
    if (we) write(a, mosi, sel);
    else miso = read(a);
    ack = true;
}

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2 || !load_elf(argv[1])) return std::printf("usage: seal_core_tb <elf>\n"), 2;
    VVexRiscv cpu;
    cpu.externalResetVector = kRam;
    cpu.timerInterrupt = cpu.softwareInterrupt = cpu.externalInterruptArray = 0;
    bool iack = false, dack = false;
    uint32_t idat = 0, ddat = 0;
    for (; cycle < kTimeout && exit_code < 0; cycle++) {
        cpu.reset = cycle < 16;
        cpu.iBusWishbone_ACK = iack, cpu.iBusWishbone_DAT_MISO = idat, cpu.iBusWishbone_ERR = 0;
        cpu.dBusWishbone_ACK = dack, cpu.dBusWishbone_DAT_MISO = ddat, cpu.dBusWishbone_ERR = 0;
        cpu.clk = 0;
        cpu.eval();
        port(iack, idat, cpu.iBusWishbone_CYC, cpu.iBusWishbone_STB, cpu.iBusWishbone_WE, cpu.iBusWishbone_ADR,
             cpu.iBusWishbone_SEL, cpu.iBusWishbone_DAT_MOSI);
        port(dack, ddat, cpu.dBusWishbone_CYC, cpu.dBusWishbone_STB, cpu.dBusWishbone_WE, cpu.dBusWishbone_ADR,
             cpu.dBusWishbone_SEL, cpu.dBusWishbone_DAT_MOSI);
        cpu.clk = 1;
        cpu.eval();
    }
    std::printf("EXIT %d GUARD %llu UNMAPPED %llu CYCLES %llu\n", exit_code, (unsigned long long)guard,
                (unsigned long long)unmapped, (unsigned long long)cycle);
    return (exit_code == 0 && guard == 0 && unmapped == 0) ? 0 : 1;
}
