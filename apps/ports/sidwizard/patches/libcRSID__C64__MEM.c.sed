# Any access to the I/O page brings the CIAs and the VIC up to date first (kestrel_sw_clock.c sw_io_touch), and a
# write to the SID is noted for BARD (kestrel_sw_sid.h), a
# read of $DC01 (CIA1 port B, the keyboard rows) computes the key matrix (lazy EmulateKeyMatrix: C64.c.sed).
s|^#include "C64.h"|&\nstatic void sw_io_touch(void); static void sw_io_write(unsigned short address); /* kestrel: kestrel_sw_clock.c */|
s|^ if ( MOSTLY (BankPointer != cRSID_C64.IObankRD) ) return \&( BankPointer\[ address \] );|&\n sw_io_touch(); /* kestrel */\n if ( RARELY (address == 0xDC01) ) { EmulateKeyMatrix(); return \&( BankPointer[ address ] ); } /* kestrel: lazy key matrix */|
s|^ if ( MOSTLY (BankPointer != cRSID_C64.IObankWR) ) return \&( BankPointer\[ address \] );| if ( RARELY (BankPointer == cRSID_C64.IObankWR) ) sw_io_write(address); /* kestrel */\n&|
