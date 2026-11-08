# Not the PC platform: CRSID_PLATFORM_PC adds a 2,000-entry playlist (2 MB) to cRSID_Interface, SDL/ALSA sound
# and the .sid file loader; the cart has its own host (kestrel_sw.c).
s|^ #define CRSID_PLATFORM_PC 1| /* kestrel: CRSID_PLATFORM_PC left undefined (patches/SIDwizard.h.sed) */|
