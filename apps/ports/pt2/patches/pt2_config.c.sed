# KESTREL: pt2 keeps one fixed sample pool, 33 slots x maxSampleLength, and a load holds two (old song + new).
# The 3 MiB cart window (HW 1.13.0) leaves pt2 a 2.60 MB heap, ~1.07 MB of it taken by everything else, and
# a load also holds the file and a 127 KB buffer. 13312 (2 x 439 KB) is the largest multiple of 512 that loads
# RONKEN.MOD over HYBRID.MOD and back (13824 fails: the heap is free enough but fragmented; measured with
# the KESTREL_AUTOLOAD build). Samples longer than 13 KB are cut at load (RONKEN's longest is 26000 bytes).
s/^\tconfig.maxSampleLength = 65534;/\tconfig.maxSampleLength = 13312; \/* KESTREL *\//
s/^\t\t\t\tconfig.maxSampleLength = 131070;/\t\t\t\tconfig.maxSampleLength = 13312; \/* KESTREL *\//
s/^\tconfig.hwMouse = true;/\tconfig.hwMouse = false; \/* KESTREL: pt2 draws its own Amiga pointer *\//
