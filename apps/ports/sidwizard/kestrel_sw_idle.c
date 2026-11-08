/* Skipping SID-Wizard's idle loop (SW_SID_ON_BARD; included by kestrel_sw.c).
 *
 * The editor's main loop (1.97, at $082D) polls two flags its IRQ sets and a quit flag, and does nothing else
 * until one is set:
 *     $082D  lda #flag1 ; beq $0839 ; jsr $1B42 ; lda #0 ; sta $082E    flag1 = $082E, set by the IRQ
 *     $0839  jsr $0AF4  ->  $0AF4 lda #flag2 ; beq $0B65 ... $0B65 rts   flag2 = $0AF5, set by the IRQ
 *     $083C  lda $B995 ; beq $082D ; jmp $B256                           the quit flag
 * A quarter of the main program's time went round it (the PC profile, SW_PROFILE_PC). Only an interrupt can
 * end it, so while the 6502 sits in it with the three flags clear, it waits in libcRSID's idle state instead
 * (Finished = 1: the clock, the CIAs and the VIC go on; the next IRQ or NMI pushes the PC where it was and
 * clears Finished, and the loop goes on after the RTI exactly where it stood). The C64 sees the same program
 * at the same time; only the main program's place inside its loop at the IRQ differs, which it cannot see.
 * The loop's code is checked byte for byte before each skip: another program (or version) is never touched. */

enum { I_FLAG = 0x04, Z_FLAG = 0x02 };

static const uint8_t sw_idle_main[23] = {      /* $082D..$0843, the flag operand at $082E excepted */
    0xa9, 0x00, 0xf0, 0x08, 0x20, 0x42, 0x1b, 0xa9, 0x00, 0x8d, 0x2e, 0x08,
    0x20, 0xf4, 0x0a, 0xad, 0x95, 0xb9, 0xf0, 0xec, 0x4c, 0x56, 0xb2 };
static const uint8_t sw_idle_sub[4] = { 0xa9, 0x00, 0xf0, 0x6d };   /* $0AF4..$0AF7, the operand at $0AF5 excepted */
static uint32_t sw_idle_skips;                 /* waits started (the README's numbers) */

static int sw_idle_code_ok(const uint8_t *ram)
{
    for (int i = 0; i < 23; i++) if (i != 1 && ram[0x082d + i] != sw_idle_main[i]) return 0;
    for (int i = 0; i < 4; i++) if (i != 1 && ram[0x0af4 + i] != sw_idle_sub[i]) return 0;
    return ram[0x0b65] == 0x60;
}

/* Before a C64 sample: wait for the next interrupt if the main program is going round the idle loop. */
static void sw_idle_step(void)
{
#ifdef SW_IDLE_OFF                             /* the before of a before/after */
    return;
#endif
    const uint8_t *ram = cRSID_C64.RAMbank;
    uint16_t pc = cRSID_C64.CPU.PC;
    uint8_t st = cRSID_C64.CPU.ST;
    if (cRSID_C64.Finished || (st & I_FLAG)) return;
    switch (pc) {
    case 0x082d: case 0x0839: case 0x083c: case 0x0af4: case 0x0b65: break; /* the next test reads RAM afresh */
    case 0x082f: case 0x083f: case 0x0af6: if (!(st & Z_FLAG)) return; break; /* a beq that will branch on */
    default: return;
    }
    if (ram[0x082e] | ram[0x0af5] | ram[0xb995]) return;
    if (!sw_idle_code_ok(ram)) return;
    cRSID_C64.Finished = 1;
    sw_idle_skips++;
}
