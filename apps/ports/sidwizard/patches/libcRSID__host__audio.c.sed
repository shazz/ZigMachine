# cRSID_generateSound() (unused here: the cart calls cRSID_generateSample()) needs the frame size that only the
# PC platform part defines.
/^void cRSID_generateSound /i #ifndef CRSID_PLATFORM_PC\nenum { SAMPLE_FRAMESIZE = 4 }; /* kestrel: patches/libcRSID__host__audio.c.sed */\n#endif
