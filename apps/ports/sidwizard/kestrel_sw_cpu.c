/* One C64 sample with the 6502 in registers (SW_SID_ON_BARD; included by kestrel_sw.c after libcRSID).
 *
 * The same machine as libcRSID's cRSID_emulateC64() in RealSID mode (C64.c's loop, kestrel-patched: the CIAs and
 * the VIC at their next event, the SID on BARD) and cRSID_emulateCPU() (CPU.c), instruction for instruction,
 * cycle for cycle, quirk for quirk: the same decoding by opcode bit groups, the same flag arithmetic on the same
 * types (A and SP short, PC an unsigned int never wrapped), the same timings (no branch page-cross cycle, the
 * same-page discount on indexed reads), the same illegal opcodes, the same stale Addr for the opcodes that set none.
 * apps/sidwizard_cpu_check.mjs runs both on random machines, opcode by opcode, and compares the whole C64.
 *
 * What differs is only where the state lives. Upstream kept the 6502 in the cRSID_C64.CPU struct and called a
 * function per instruction: on ZIGGY (wasm -> rv32) every register access was a load or a store, ~215 rv32
 * instructions per 6502 instruction. Here the registers are locals for the whole sample, and memory goes straight
 * to the bank the PLA maps (MemoryBankPointersRD, the table rd() used) unless the page is I/O: I/O reads and the
 * writes to $D000-$DFFF go through upstream's own rd(), wr(), wr2() (the I/O hand-over, the CIA/VIC acks, the
 * SID's notes for BARD, the colour-RAM mirror), so everything the I/O sees is upstream's. */

#pragma push_macro("rd")                       /* host/file.h redefines rd()/wr() as plain RAM accesses for its */
#pragma push_macro("wr")                       /* disk traps: here they are CPU.c's, the I/O-aware ones */
#undef rd
#undef wr
#ifdef SW_PROFILE_PC
static uint32_t sw_io_hist[0x1000];
static __attribute__((noinline)) unsigned char sw_rd_io(unsigned short a) { sw_io_hist[a & 0xFFF]++; return rd(a); }
#else
static __attribute__((noinline)) unsigned char sw_rd_io(unsigned short a) { return rd(a); }
#endif
static __attribute__((noinline)) void sw_wr_io(unsigned short a, unsigned char v) { wr(a, v); }
static __attribute__((noinline)) void sw_wr2_io(unsigned short a, unsigned char v) { wr2(a, v); }
#pragma pop_macro("wr")
#pragma pop_macro("rd")

static inline unsigned char sw_rd(unsigned char *const *rt, const unsigned char *io, unsigned short a)
{
    unsigned char *p = rt[a >> 8];
    return MOSTLY(p != io) ? p[a] : sw_rd_io(a);
}

/* The 6502's registers and helpers, as CPU.c's, on the locals of sw_emulate_c64(). (The I/O hand-over's counters
 * stay globals: as locals, stored and taken back around every I/O call, they saved 5 % and cost 1 KB of code.) */
#define SW_BANKS() ((unsigned char *const *)cRSID_C64.MemoryBankPointersRD[ram[1] & 3])  /* the PLA's read map now */
#define RD(a) sw_rd(rt, io, (unsigned short)(a))
#define SW_WRITE(a, v, slow) do { unsigned short a_ = (unsigned short)(a); unsigned char v_ = (unsigned char)(v);         \
    if (a_ < 0xD000 || a_ >= 0xE000) { ram[a_] = v_; if (a_ < 2) rt = SW_BANKS(); } \
    else slow(a_, v_); } while (0)
#define WR(a, v) SW_WRITE(a, v, sw_wr_io)
#define WR2(a, v) SW_WRITE(a, v, sw_wr2_io)
#define clrC() (ST &= ~C)
#define setC(e) do { unsigned char e_ = (unsigned char)(e); ST &= ~C; ST |= (e_ != 0); } while (0)
#define clrNZC() (ST &= ~(N | Z | C))
#define setNZbyA() do { ST &= ~(N | Z); ST |= ((!A) << 1) | (A & N); } while (0)
#define setNZbyT(t) do { short t_ = (short)(t); t_ &= 0xFF; ST &= ~(N | Z); ST |= ((!t_) << 1) | (t_ & N); } while (0)
#define setNZbyX() do { ST &= ~(N | Z); ST |= ((!X) << 1) | (X & N); } while (0)
#define setNZbyY() do { ST &= ~(N | Z); ST |= ((!Y) << 1) | (Y & N); } while (0)
#define setNZbyM() do { ST &= ~(N | Z); ST |= ((!RD(Addr)) << 1) | (RD(Addr) & N); } while (0)
#define setNZCbyAdd() do { ST &= ~(N | Z | C); ST |= (A & N) | (A > 255); A &= 0xFF; ST |= (!A) << 1; } while (0)
#define setVbyAdd(m, t) do { unsigned char m_ = (unsigned char)(m); short t2_ = (short)(t); ST &= ~V;              \
    ST |= ((~(t2_ ^ m_)) & (t2_ ^ A) & N) >> 1; } while (0)
#define setNZCbySub(t) do { signed short t_ = (signed short)(t); ST &= ~(N | Z | C); ST |= (t_ & N) | (t_ >= 0);   \
    ST |= ((!(t_ & 0xFF)) << 1); } while (0)
#define push(v) do { ram[0x100 + SP] = (unsigned char)(v); --SP; SP &= 0xFF; } while (0)
#define pop() (++SP, SP &= 0xFF, ram[0x100 + SP])
#define mImm() do { ++PC; Addr = PC; Cycles = 2; } while (0)
#define mZp() do { ++PC; Addr = RD(PC); Cycles = 3; } while (0)
#define mAbs() do { ++PC; Addr = RD(PC); ++PC; Addr += RD(PC) << 8; Cycles = 4; } while (0)
#define mZpX() do { ++PC; Addr = (RD(PC) + X) & 0xFF; Cycles = 4; } while (0)
#define mZpY() do { ++PC; Addr = (RD(PC) + Y) & 0xFF; Cycles = 4; } while (0)
#define mAbsX() do { ++PC; Addr = RD(PC) + X; ++PC; SamePage = (Addr <= 0xFF); Addr += RD(PC) << 8; Cycles = 5; } while (0)
#define mAbsY() do { ++PC; Addr = RD(PC) + Y; ++PC; SamePage = (Addr <= 0xFF); Addr += RD(PC) << 8; Cycles = 5; } while (0)
#define mIndY() do { ++PC; Addr = RD(RD(PC)) + Y; SamePage = (Addr <= 0xFF);                                     \
    Addr += RD((RD(PC) + 1) & 0xFF) << 8; Cycles = 6; } while (0)
#define mXInd() do { ++PC; Addr = (RD(RD(PC) + X) & 0xFF) + ((RD(RD(PC) + X + 1) & 0xFF) << 8); Cycles = 6; } while (0)

static const unsigned char sw_flag_switches[] = { 0x01, 0x21, 0x04, 0x24, 0x00, 0x40, 0x08, 0x28 }, /* CPU.c's tables */
    sw_branch_flags[] = { 0x80, 0x40, 0x01, 0x02 };

/* cRSID_emulateC64() for this cart's machine (RealSID, one SID, the light engine off: the SID is on BARD). */
static void sw_emulate_c64(void)
{
    cRSID_CPUinstance *cpu = &cRSID_C64.CPU;
    unsigned char *const ram = cRSID_C64.RAMbank;
    const unsigned char *const io = cRSID_C64.IObankRD;
    unsigned char *const *rt = SW_BANKS();
    unsigned int PC = cpu->PC, Addr = cpu->Addr, Cycles = cpu->Cycles, SamePage = cpu->SamePage;
    short A = cpu->A, SP = cpu->SP, T;
    unsigned char X = cpu->X, Y = cpu->Y, ST = cpu->ST, prevnmi = cpu->PrevNMI, IR;
    char finished = cRSID_C64.Finished;
    short scc = cRSID_C64.SampleCycleCnt;
    const short ratio = (short)cRSID_C64.SampleClockRatio;
    unsigned char ic;

    while (scc <= ratio) {
        unsigned char nmi = cRSID_C64.NMI;
        if (RARELY(nmi > prevnmi)) {                     /* handleCPUinterrupts(): NMI first */
            push(PC >> 8); push(PC & 0xFF); push(ST); ST |= I;
            PC = RD(0xFFFA) + (RD(0xFFFB) << 8); prevnmi = nmi; finished = 0; ic = 7;
        } else if (RARELY(cRSID_C64.IRQ && !(ST & I))) {
            push(PC >> 8); push(PC & 0xFF); push(ST); ST |= I;
            PC = RD(0xFFFE) + (RD(0xFFFF) << 8); prevnmi = nmi; finished = 0; ic = 7;
        } else {
            prevnmi = nmi;
            if (MOSTLY(!finished)) {
#include "kestrel_sw_cpu_step.h"                 /* sets ic (0xFE/0xFF: returned out of the call) */
                if (RARELY(ic >= 0xFE)) { finished = 1; ic = 6; }
            } else {                                     /* waiting: to the next CIA/VIC event (sw_idle_cycles) */
                unsigned n = sw_io_due > sw_io_cycles ? sw_io_due - sw_io_cycles : 1;
                unsigned left = ((unsigned)(ratio - scc) >> CRSID_CLOCK_FRACTIONAL_BITS) + 1;
                if (n > left) n = left;
                ic = (unsigned char)(n > 255 ? 255 : n);
            }
        }
        sw_io_cycles += ic;
        if (RARELY(sw_io_cycles >= sw_io_due)) sw_io_flush();
        scc += (short)(ic << CRSID_CLOCK_FRACTIONAL_BITS);
    }
    scc -= ratio;
    cpu->PC = PC; cpu->Addr = Addr; cpu->A = A; cpu->SP = SP; cpu->X = X; cpu->Y = Y; cpu->ST = ST;
    cpu->PrevNMI = prevnmi; cpu->Cycles = Cycles; cpu->SamePage = SamePage;
    cRSID_C64.Finished = finished;
    cRSID_C64.SampleCycleCnt = scc;
    handleCHRIO();
}
