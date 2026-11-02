# KESTREL: the 12 screen bitmaps are decoded on demand (kestrel_bmp.c), not at boot: -1 MB of heap.
s/^\t\(\(samplerScreen\|samplerVolume\|samplerFilters\|diskOpScreen\|posEd\|spectrumVisuals\|editOpScreen[1-4]\|aboutScreen\|samplingBox\)BMP = unpackBMP\)/\t\/* KESTREL lazy *\/ \/\/ \1/
s/\b\(samplerScreen\|samplerVolume\|samplerFilters\|diskOpScreen\|posEd\|spectrumVisuals\|editOpScreen[1-4]\|aboutScreen\|samplingBox\)BMP *== NULL/0 \/* KESTREL lazy *\//g
