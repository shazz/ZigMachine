# A read of $DC01 (CIA1 port B, the keyboard rows) computes the matrix first: lazy EmulateKeyMatrix (C64.c.sed).
s|^ else if ( MOSTLY (address < 0xD400 \|\| 0xD419 <= address) ) return \&( BankPointer\[ address \] );| else if ( RARELY (address == 0xDC01) ) { EmulateKeyMatrix(); return \&( BankPointer[ address ] ); } /* kestrel: lazy key matrix */\n&|
