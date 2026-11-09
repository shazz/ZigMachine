/* kestrel_sw_cpu.c against libcRSID's own 6502, on random machines (SW_CPU_TEST builds only: make cputest;
 * apps/sidwizard_cpu_check.mjs runs it). Each case is a whole C64 (cRSID_C64, the I/O hand-over's counters) with
 * random registers, memory map, RAM and pending I/O cycles, run once by each side from the same snapshot; the two
 * C64s after it must be byte for byte the same.
 *   op:     every opcode, one instruction: sw_cpu_step() vs cRSID_emulateCPU() (cycles and return code too)
 *   sample: one C64 sample from random code: sw_emulate_c64() vs cRSID_emulateC64() (interrupts, waiting, I/O)
 * SW_CPU_BREAK plants a wrong carry in the fast ADC (the check's --break: the test must then fail). */

static cRSID_C64instance sw_t0, sw_t1;
static unsigned sw_tio0[3], sw_tio1[3];
static unsigned long long sw_tcyc0, sw_tcyc1;
static uint32_t sw_rng = 0x2545F491u;

static uint32_t sw_rand(void) { sw_rng ^= sw_rng << 13; sw_rng ^= sw_rng >> 17; sw_rng ^= sw_rng << 5; return sw_rng; }

static void sw_tsave(cRSID_C64instance *s, unsigned *io, unsigned long long *cyc)
{
    memcpy(s, &cRSID_C64, sizeof *s);
    io[0] = sw_io_cycles; io[1] = sw_io_due; io[2] = (unsigned)sw_sid_reg; *cyc = sw_cycle;
}

static void sw_tload(const cRSID_C64instance *s, const unsigned *io, unsigned long long cyc)
{
    memcpy(&cRSID_C64, s, sizeof *s);
    sw_io_cycles = io[0]; sw_io_due = io[1]; sw_sid_reg = (int)io[2]; sw_cycle = cyc;
}

/* One instruction of kestrel_sw_cpu_step.h on the struct's registers. */
static unsigned char sw_cpu_step(void)
{
    cRSID_CPUinstance *cpu = &cRSID_C64.CPU;
    unsigned char *const ram = cRSID_C64.RAMbank;
    const unsigned char *const io = cRSID_C64.IObankRD;
    unsigned char *const *rt = SW_BANKS();
    unsigned int PC = cpu->PC, Addr = cpu->Addr, Cycles = cpu->Cycles, SamePage = cpu->SamePage;
    short A = cpu->A, SP = cpu->SP, T;
    unsigned char X = cpu->X, Y = cpu->Y, ST = cpu->ST, IR, ic;
#include "kestrel_sw_cpu_step.h"
    cpu->PC = PC; cpu->Addr = Addr; cpu->A = A; cpu->SP = SP; cpu->X = X; cpu->Y = Y; cpu->ST = ST;
    cpu->Cycles = Cycles; cpu->SamePage = SamePage;
    return ic;
}

static void sw_trandom(int fill, unsigned op)
{
    unsigned char *ram = cRSID_C64.RAMbank;
    if (fill) for (int a = 2; a < 0x10000; a++) ram[a] = (unsigned char)sw_rand();
    ram[1] = (unsigned char)(0x30 | (sw_rand() & 7));
    ram[diskZPloadStatus] = 0;                    /* no disk trap (it would read the host's files twice) */
    cRSID_CPUinstance *cpu = &cRSID_C64.CPU;
    cpu->PC = (sw_rand() & 7) ? sw_rand() % 0xA000 : sw_rand() & 0xFFFF;
    if (op < 256) ram[cpu->PC] = (unsigned char)op;
    cpu->A = (short)(sw_rand() & 0xFF); cpu->X = (unsigned char)sw_rand(); cpu->Y = (unsigned char)sw_rand();
    cpu->ST = (unsigned char)sw_rand(); cpu->SP = (short)((sw_rand() & 3) ? sw_rand() & 0xFF : 0xFF);
    cpu->Addr = sw_rand() & 0xFFFF; cpu->PrevNMI = (unsigned char)(sw_rand() & 1);
    cRSID_C64.Returned = (char)(sw_rand() & 1);
    cRSID_C64.IRQ = (unsigned char)(sw_rand() & 1); cRSID_C64.NMI = (unsigned char)(sw_rand() & 1);
    cRSID_C64.Finished = (char)((sw_rand() & 3) == 0);
    cRSID_C64.SampleCycleCnt = (short)(sw_rand() % cRSID_C64.SampleClockRatio);
    sw_io_cycles = sw_rand() % 64; sw_io_due = sw_io_cycles + sw_rand() % 64;
}

static int sw_tcompare(const char *what, unsigned op, unsigned r1, unsigned r2)
{
    const unsigned char *a = (const unsigned char *)&sw_t1, *b = (const unsigned char *)&cRSID_C64;
    size_t at = 0;
    while (at < sizeof sw_t1 && a[at] == b[at]) at++;
    int io = memcmp(sw_tio1, (unsigned[]){ sw_io_cycles, sw_io_due, (unsigned)sw_sid_reg }, sizeof sw_tio1) || sw_tcyc1 != sw_cycle;
    if (at == sizeof sw_t1 && !io && r1 == r2) return 0;
    char m[128];
    snprintf(m, sizeof m, "cpu test %s: op %02x pc %04x: differs at struct+%u (CPU at +%u) ret %u/%u io %d", what, op,
             sw_t0.CPU.PC, (unsigned)at, (unsigned)offsetof(cRSID_C64instance, CPU), r1, r2, io);
    kestrel_log(m);
    snprintf(m, sizeof m, "  addr %04x->%04x/%04x bank %d io0 %u %u io1 %u %u up %u %u irq %d/%d", sw_t0.CPU.Addr, sw_t1.CPU.Addr,
             cRSID_C64.CPU.Addr, sw_t0.RAMbank[1] & 3, sw_tio0[0], sw_tio0[1], sw_tio1[0], sw_tio1[1], sw_io_cycles, sw_io_due,
             sw_t1.IRQ, cRSID_C64.IRQ);
    kestrel_log(m);
    return 1;
}

static void sw_cpu_test(void)
{
    int bad = 0, cases = 0;
    for (unsigned op = 0; op < 256; op++)
        for (int k = 0; k < 48; k++, cases++) {
            sw_trandom(k == 0 && (op & 15) == 0, op);
            sw_tsave(&sw_t0, sw_tio0, &sw_tcyc0);
            unsigned r1 = sw_cpu_step();
            sw_tsave(&sw_t1, sw_tio1, &sw_tcyc1);
            sw_tload(&sw_t0, sw_tio0, sw_tcyc0);
            unsigned r2 = cRSID_emulateCPU();
            if (sw_tcompare("op", op, r1, r2) && ++bad > 20) goto out;
        }
    for (int k = 0; k < 4000; k++, cases++) {
        sw_trandom((k & 63) == 0, 256);
        sw_tsave(&sw_t0, sw_tio0, &sw_tcyc0);
        sw_emulate_c64();
        sw_tsave(&sw_t1, sw_tio1, &sw_tcyc1);
        sw_tload(&sw_t0, sw_tio0, sw_tcyc0);
        cRSID_emulateC64();
        if (sw_tcompare("sample", cRSID_C64.RAMbank[sw_t0.CPU.PC & 0xFFFF], 0, 0) && ++bad > 20) goto out;
    }
out:;
    char m[96];
    snprintf(m, sizeof m, "cpu test: %d cases, %d differ (%u-byte C64)", cases, bad, (unsigned)sizeof sw_t1);
    kestrel_log(m);
}
