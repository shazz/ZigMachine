# KESTREL: the screen is 320x240 at scale 1 (no config file on the read-only floppy, so the defaults stick),
# and the fake "decrunch" intro (nostalgy.c) is skipped.
s/^\tmused.window_w = 640;$/\tmused.window_w = 320;/
s/^\tmused.window_h = 480;$/\tmused.window_h = 240;/
s/MULTIKEY_JAMMING|START_WITH_TEMPLATE|EDIT_SEQUENCE_DIGITS;/MULTIKEY_JAMMING|START_WITH_TEMPLATE|EDIT_SEQUENCE_DIGITS|DISABLE_NOSTALGY;/
# 22.05 kHz mixing: a bus's reverb (2 s delay line) and chorus (4 s LUT) cost 345 + 353 KiB at this rate, twice
# that at 44.1 kHz, which leaves no room for both in the 2 MiB cart window (README.md "Memory").
s/^\tmused.mix_rate = 44100;$/\tmused.mix_rate = 22050;/
