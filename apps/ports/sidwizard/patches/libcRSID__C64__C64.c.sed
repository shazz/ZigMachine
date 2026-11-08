# The 1 MHz parts clocked less often with the same results (kestrel_sw_clock.c): the CIAs and the VIC at their
# next event or an I/O access, the SID's envelopes once a sample; and the keyboard matrix only when $DC01 is read
# (libcRSID__C64__MEM.c.sed), not after every instruction (upstream walked it ~300,000 times a second).
/^cRSID_Output\* cRSID_emulateC64 () {/i #include "kestrel_sw_clock.c" /* kestrel */
/^   cRSID_C64.IRQ = cRSID_C64.NMI = 0; \/\/prepare for collecting IRQ sources/d
s|^   cRSID_C64.IRQ \|= cRSID_emulateCIA( \&cRSID_C64.CIA\[1\], InstructionCycles ); EmulateKeyMatrix();|   sw_io_cycles += InstructionCycles; if ( RARELY (sw_io_cycles >= sw_io_due) ) sw_io_flush(); /* kestrel: CIAs + VIC, EmulateKeyMatrix on a $DC01 read */|
/^   cRSID_C64.NMI |= cRSID_emulateCIA( &cRSID_C64.CIA\[2\], InstructionCycles );/d
/^   cRSID_C64.IRQ |= cRSID_emulateVIC( InstructionCycles );/d
s|^  cRSID_emulateADSRs( \&cRSID_C64.SID\[1\], InstructionCycles );|  sw_adsr_cycles += InstructionCycles; /* kestrel: kestrel_sw_clock.c */|
s|^ cRSID_C64.SampleCycleCnt -= cRSID_C64.SampleClockRatio;|&\n sw_emulate_adsrs(); /* kestrel */|
# The SID on the sound side (kestrel_sw_sid.h SW_SID_ON_BARD): no light-engine render here.
s|^ else Output = cRSID_emulateLightSIDs();| else if (!SW_SID_ON_BARD) Output = cRSID_emulateLightSIDs(); /* kestrel: kestrel_sw_sid.h */|
