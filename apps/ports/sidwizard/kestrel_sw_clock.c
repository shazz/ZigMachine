/* The 1 MHz parts of the C64 clocked less often, with the same results (included into libcRSID's C64.c before
 * cRSID_emulateC64() by patches/libcRSID__C64__C64.c.sed). Upstream ran the CIAs, the VIC and the SID's
 * envelopes after every 6502 instruction (~5,100 a frame); on ZIGGY that was most of the cart's time
 * (README.md, "Cost").
 *
 * CIAs and VIC (sw_io_*): cycles are summed and handed over at the instruction that reaches the next event:
 * the next raster line (the VIC's raster IRQ and its per-line bookkeeping), a CIA timer reaching zero, or any
 * access to the I/O page ($D000-$DFFF, MEM.c calls sw_io_touch() first): a register read sees the time up to
 * the instruction before, a write is clocked from the instruction after, as upstream. Their IRQ/NMI lines
 * change only there, so they stay as the last hand-over left them.
 *
 * Envelopes (sw_emulate_adsrs): once a sample (~14 instructions at 22.05 kHz). cRSID_emulateADSRs() fires its
 * rate counter at most once a call, so the cycles are fed in steps shorter than the shortest rate period a
 * voice can be in before the next call. The envelope counts as upstream; a gate change is seen up to one sample
 * (45 cycles) later, and a voice holding at its sustain level (or silent after its release) sets no limit: its
 * rate counter's ticks there move only the exponent counter, which restarts at the next level change. */
static unsigned sw_io_cycles, sw_io_due;
#if SW_SID_ON_BARD
static int sw_sid_reg = -1;                    /* a SID register written by this instruction (kestrel_sw_sid.h) */
static unsigned long long sw_cycle;            /* C64 cycles handed over so far */
#endif

static unsigned sw_cia_due(cRSID_CIAinstance *cia, unsigned due)
{
    unsigned char ca = cia->BasePtrWR[0xE], cb = cia->BasePtrWR[0xF];
    if ((ca | cb) & 0x10) return 0;                                       /* a force-load strobe: at once */
    if ((ca & 0x21) == 0x01) { unsigned t = (cia->BasePtrRD[5] << 8 | cia->BasePtrRD[4]) + 1u; if (t < due) due = t; }
    if ((cb & 0x41) == 0x01) { unsigned t = (cia->BasePtrRD[7] << 8 | cia->BasePtrRD[6]) + 1u; if (t < due) due = t; }
    return due;
}

static void sw_io_flush(void)
{
    char c = (char)sw_io_cycles;
    cRSID_C64.IRQ = cRSID_C64.NMI = 0;
    cRSID_C64.IRQ |= cRSID_emulateCIA(&cRSID_C64.CIA[1], c);
    cRSID_C64.NMI |= cRSID_emulateCIA(&cRSID_C64.CIA[2], c);
    cRSID_C64.IRQ |= cRSID_emulateVIC(c);
#if SW_SID_ON_BARD
    sw_cycle += sw_io_cycles;
    if (sw_sid_reg >= 0) { sw_sid_write((unsigned)sw_sid_reg, cRSID_C64.IObankWR[0xD400 + sw_sid_reg], sw_cycle); sw_sid_reg = -1; }
#endif
    sw_io_cycles = 0;
    unsigned due = cRSID_C64.VIC.RasterRowCycles - cRSID_C64.VIC.RowCycleCnt;
    sw_io_due = sw_cia_due(&cRSID_C64.CIA[2], sw_cia_due(&cRSID_C64.CIA[1], due));
}

/* An I/O register is about to be read or written: everything up to now first, and a hand-over after this
 * instruction (its write may start a timer or acknowledge an IRQ). */
static void sw_io_touch(void)
{
    if (sw_io_cycles) sw_io_flush();
    sw_io_due = 0;
}

/* A read that needs no hand-over (MEM.c), when no SID write waits to be stamped (the hand-over is what stamps it):
 *   CIA1's ports, $DC00-$DC03 (the keyboard), which the CIA's clock never changes;
 *   the VIC's raster line and IRQ flags, $D011, $D012, $D019, which change only when a line ends: an event, and
 *   the pending cycles never reach one (sw_io_due), so a hand-over now would not change what is read.
 * The CIAs and the VIC then catch up at their next event as if the read had not happened: the same machine,
 * without the ~400-cycle hand-over for each read of a loop that polls them (the file browser's IRQ waits for a
 * raster line reading $D012 ~1,750 times a frame). */
static int sw_io_clockless(unsigned short address)
{
#ifdef SW_IO_TOUCH_ALL                         /* the before of a before/after */
    return 0;
#endif
#if SW_SID_ON_BARD
    if (sw_sid_reg >= 0) return 0;
#endif
    return (address & 0xFFFC) == 0xDC00 || address == 0xD012 || address == 0xD011 || address == 0xD019;
}

/* An I/O register is about to be written (MEM.c): the same, and a SID register is noted for BARD. */
static void sw_io_write(unsigned short address)
{
    sw_io_touch();
#if SW_SID_ON_BARD
    if (address >= 0xD400 && address < 0xD800) sw_sid_reg = address & 0x1F;
#else
    (void)address;
#endif
}

/* The 6502 waiting (libcRSID's idle state: between IRQs, or held by kestrel_sw_idle.c / kestrel_sw_pace.c):
 * upstream counted it 7 cycles at a time; it now goes straight to the CIAs'/VIC's next event (where the IRQ that
 * ends the wait is raised), never past the end of the C64 sample. */
static unsigned char sw_idle_cycles(void)
{
    unsigned n = sw_io_due > sw_io_cycles ? sw_io_due - sw_io_cycles : 1;
    unsigned left = ((unsigned)(cRSID_C64.SampleClockRatio - cRSID_C64.SampleCycleCnt) >> CRSID_CLOCK_FRACTIONAL_BITS) + 1;
    if (n > left) n = left;
    return (unsigned char)(n > 255 ? 255 : n);
}

static unsigned sw_adsr_cycles;
static const unsigned short sw_adsr_period[16] = { 9, 32, 63, 95, 149, 220, 267, 313, 392, 977, 1954, 3126, 3907, 11720, 19532, 31251 };

static unsigned sw_adsr_step(cRSID_SIDinstance *sid)
{
    unsigned p = 0xFFFF;
    for (int ch = 0; ch < 21; ch += 7) {
        unsigned char ad = sid->BasePtr[ch + 5], sr = sid->BasePtr[ch + 6], st = sid->ADSRstate[ch];
        unsigned a = sw_adsr_period[ad >> 4], d = sw_adsr_period[ad & 15], r = sw_adsr_period[sr & 15], q;
        unsigned char env = sid->EnvelopeCounter[ch];
        if (!(sid->BasePtr[ch + 4] & 1)) q = (st & 0x01) || env ? r : 0xFFFF;  /* release (none left at 0) */
        else if (!(st & 0x01) || (st & 0x80)) q = a < d ? a : d;          /* attack now (or soon), then decay */
        else q = env == (sr & 0xF0) + (sr >> 4) ? 0xFFFF : d;             /* decay; at the sustain level it holds */
        if (q < p) p = q;
    }
    return p - 1 < 127 ? p - 1 : 127;                                     /* cRSID_emulateADSRs takes a char */
}

static void sw_emulate_adsrs(void)
{
#if SW_SID_ON_BARD
    sw_adsr_cycles = 0;                        /* the envelopes are the sound side's (kestrel_sw_sid.h) */
    return;
#endif
    cRSID_SIDinstance *sid = &cRSID_C64.SID[1];
    unsigned c = sw_adsr_cycles, step = sw_adsr_step(sid);
    sw_adsr_cycles = 0;
    while (c) {
        unsigned k = c < step ? c : step;
        cRSID_emulateADSRs(sid, (char)k);
        c -= k;
    }
}
