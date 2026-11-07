# The dither LFSR is a function static: it outlives a tune, so a tune's output depended on what
# played before it. LFSR becomes zm_crsid_lfsr (config/zm_crsid.h), reset by every zm_sid_load.
s/^ static int LFSR = 0x0055A5AA; FASTVAR int fb;$/ FASTVAR int fb;/
