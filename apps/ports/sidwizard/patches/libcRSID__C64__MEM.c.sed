# Any access to the I/O page brings the CIAs and the VIC up to date first (kestrel_sw_clock.c sw_io_touch), and a
# write to the SID is noted for BARD (kestrel_sw_sid.h), a
# read of $DC01 (CIA1 port B, the keyboard rows) computes the key matrix (lazy EmulateKeyMatrix: C64.c.sed).
# CIA1's ports and the VIC's raster registers are read without that hand-over (kestrel_sw_clock.c sw_io_clockless):
# what they hold cannot change before the next CIA/VIC event, and a loop polling them read them ~2,000 times a frame.
s|^#include "C64.h"|&\nstatic void sw_io_touch(void); static void sw_io_write(unsigned short address); static int sw_io_clockless(unsigned short address); /* kestrel: kestrel_sw_clock.c */|
s|^ if ( MOSTLY (BankPointer != cRSID_C64.IObankRD) ) return \&( BankPointer\[ address \] );|&\n if ( RARELY (sw_io_clockless(address)) ) { if (address == 0xDC01) EmulateKeyMatrix(); return \&( BankPointer[ address ] ); } /* kestrel */\n sw_io_touch(); /* kestrel */\n if ( RARELY (address == 0xDC01) ) { EmulateKeyMatrix(); return \&( BankPointer[ address ] ); } /* kestrel: lazy key matrix */|
s|^ if ( MOSTLY (BankPointer != cRSID_C64.IObankWR) ) return \&( BankPointer\[ address \] );| if ( RARELY (BankPointer == cRSID_C64.IObankWR) ) sw_io_write(address); /* kestrel */\n&|
