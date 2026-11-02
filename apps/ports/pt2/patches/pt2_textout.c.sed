# KESTREL: every write into video.frameBuffer marks its rectangle (kestrel_fb_dirty, kestrel_sdl.c): the
# present converts only what changed, not the whole 320x255 ARGB picture (~1.7 Mc a frame on the board).
/^void charOut(/,/^}/s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(yPos \* SCREEN_W) + xPos\];$/&\n\tkestrel_fb_dirty(xPos, yPos, FONT_CHAR_W, h);/
/^void charOut2(/,/^}/s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(yPos \* SCREEN_W) + xPos\];$/&\n\tkestrel_fb_dirty(xPos, yPos, FONT_CHAR_W + 1, h + 1); \/* and its shadow *\//
/^void charOutBg(/,/^}/s/^\tuint32_t \*dstPtr = &video.frameBuffer\[(yPos \* SCREEN_W) + xPos\];$/&\n\tkestrel_fb_dirty(xPos, yPos, FONT_CHAR_W, h);/
/^void charOutBig(/,/^}/s/^\tuint32_t \*dstPtr1 = &video.frameBuffer\[(yPos \* SCREEN_W) + xPos\];$/&\n\tkestrel_fb_dirty(xPos, yPos, FONT_CHAR_W, h * 2);/
/^void charOutBigBg(/,/^}/s/^\tuint32_t \*dstPtr1 = &video.frameBuffer\[(yPos \* SCREEN_W) + xPos\];$/&\n\tkestrel_fb_dirty(xPos, yPos, FONT_CHAR_W, FONT_CHAR_H * 2);/
