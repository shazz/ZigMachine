# The keyboard matrix is computed when $DC01 is read (patches/MEM.c.sed), not after every instruction:
# upstream walked the 8x8 matrix about 300,000 times a second.
s|cRSID_emulateCIA( \&cRSID_C64.CIA\[1\], InstructionCycles ); EmulateKeyMatrix();|cRSID_emulateCIA( \&cRSID_C64.CIA[1], InstructionCycles ); /* kestrel: EmulateKeyMatrix() on a $DC01 read (MEM.c) */|
