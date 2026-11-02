# KESTREL: pt2 keeps one fixed sample pool, 33 slots x maxSampleLength, and a load holds two (old song + new).
# ProTracker's 65534 needs 2 x 2.16 MB, more than the 4 MiB cart window's heap (3.65 MB); 32768 (2 x 1.08 MB)
# fits with ~170 KB to spare. Samples longer than 32 KB are cut at load.
s/^\tconfig.maxSampleLength = 65534;/\tconfig.maxSampleLength = 32768; \/* KESTREL *\//
s/^\t\t\t\tconfig.maxSampleLength = 131070;/\t\t\t\tconfig.maxSampleLength = 32768; \/* KESTREL *\//
s/^\tconfig.hwMouse = true;/\tconfig.hwMouse = false; \/* KESTREL: pt2 draws its own Amiga pointer *\//
