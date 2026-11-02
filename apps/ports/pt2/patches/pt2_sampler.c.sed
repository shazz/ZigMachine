# KESTREL: screen bitmaps decoded on demand (kestrel_bmp.c)
s/\b\(samplerScreen\|samplerVolume\|samplerFilters\|diskOpScreen\|posEd\|spectrumVisuals\|editOpScreen[1-4]\|aboutScreen\|samplingBox\)BMP\b/KBMP(\1)/g
# KESTREL: every write into video.frameBuffer marks its rectangle (kestrel_fb_dirty, kestrel_sdl.c).
s/^\t\t\tvideo.frameBuffer\[(y \* SCREEN_W) + x\] = color;$/\t\t\tkestrel_fb_dirty(x, y, 1, 1);\n&/
s/^\t\tuint32_t \*dstPtr = &video.frameBuffer\[(SAMPLE_AREA_Y_CENTER \* SCREEN_W) + 3\];$/&\n\t\tkestrel_fb_dirty(3, SAMPLE_AREA_Y_CENTER, SAMPLE_AREA_WIDTH, 1);/
s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(138 \* SCREEN_W) + (start + 3)\];$/&\n\tkestrel_fb_dirty(start + 3, 138, rangeLen, 64);/
s/^\tmemcpy(&video.frameBuffer\[(\?121 \* SCREEN_W)\?\], /\tkestrel_fb_dirty(0, 121, 320, 134);\n&/
