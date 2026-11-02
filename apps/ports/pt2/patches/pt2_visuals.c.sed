# KESTREL: screen bitmaps decoded on demand (kestrel_bmp.c)
s/\b\(samplerScreen\|samplerVolume\|samplerFilters\|diskOpScreen\|posEd\|spectrumVisuals\|editOpScreen[1-4]\|aboutScreen\|samplingBox\)BMP\b/KBMP(\1)/g
# KESTREL: every write into video.frameBuffer marks its rectangle (kestrel_fb_dirty, kestrel_sdl.c), so the
# present converts only what changed. The VU meters draw upwards from row 187 (rows 140..187).
/^void blit32(/,/^}/s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(y \* SCREEN_W) + x\];$/&\n\tkestrel_fb_dirty(x, y, w, h);/
/^void putPixel(/,/^}/s/^\tvideo.frameBuffer\[(y \* SCREEN_W) + x\] = pixelColor;$/\tkestrel_fb_dirty(x, y, 1, 1);\n&/
/^void hLine(/,/^}/s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(y \* SCREEN_W) + x\];$/&\n\tkestrel_fb_dirty(x, y, w, 1);/
/^void vLine(/,/^}/s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(y \* SCREEN_W) + x\];$/&\n\tkestrel_fb_dirty(x, y, 1, h);/
/^void fillRect(/,/^}/s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(y \* SCREEN_W) + x\];$/&\n\tkestrel_fb_dirty(x, y, w, h);/
/^static void fillFromVuMetersBgBuffer(/,/^}/s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(187 \* SCREEN_W) + 55\];$/&\n\tkestrel_fb_dirty(55, 140, 3 * 72 + 10, 48);/
/^void renderVuMeters(/,/^}/s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(187 \* SCREEN_W) + 55\];$/&\n\tkestrel_fb_dirty(55, 140, 3 * 72 + 10, 48);/
s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(158 \* SCREEN_W) + 105\];$/&\n\tkestrel_fb_dirty(105, 158, 65, 3);/
s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(169 \* SCREEN_W) + 105\];$/&\n\tkestrel_fb_dirty(105, 169, 65, 3);/
s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(3 \* SCREEN_W) + 310\];$/&\n\tkestrel_fb_dirty(310, 3, 7, PAULA_VOICES * 11);/
s/^\t\tuint32_t \*dstPtr = &video.frameBuffer\[(59 \* SCREEN_W) + 129\];$/&\n\t\tkestrel_fb_dirty(129, 59, SPECTRUM_BAR_NUM * (SPECTRUM_BAR_WIDTH + 2), SPECTRUM_BAR_HEIGHT);/
s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(44 \* SCREEN_W) + 120\];$/&\n\tkestrel_fb_dirty(120, 44, 200, 55);/
s/^\t\tuint32_t \*dst32 = &video.frameBuffer\[(sy \* SCREEN_W) + sx\];$/&\n\t\tkestrel_fb_dirty(sx, sy, sw, sh);/
