# KESTREL: screen bitmaps decoded on demand (kestrel_bmp.c)
s/\b\(samplerScreen\|samplerVolume\|samplerFilters\|diskOpScreen\|posEd\|spectrumVisuals\|editOpScreen[1-4]\|aboutScreen\|samplingBox\)BMP\b/KBMP(\1)/g
# KESTREL: the sampling preview's centre line (kestrel_fb_dirty, kestrel_sdl.c)
s/^\tuint32_t \*centerPtr = &video.frameBuffer\[(76 \* SCREEN_W) + 123\];$/&\n\tkestrel_fb_dirty(123, 76, SAMPLE_PREVIEW_WITDH, 1);/
