/* The parts of the picture, each drawn only where it changed (included by kestrel_sw_video.c). */

/* The 26 text rows: upstream displayScreen()'s VRAM/CRAM walk (screen bank from the VIC bank and $D018 seen at
 * raster line $80, row 26 from the bank seen at line $F7, rows 25/26 coloured from the colour RAM as it was at
 * their raster lines). */
static void sw_draw_text(void)
{
    byte bank = (byte)(~VICbankBars[INSCREEN_RASTER] & 3), cs = VICbankBars[INSCREEN_RASTER] == 3 ? 0 : 1;
    const byte *vram = &cRSID_C64.RAMbank[bank * 0x4000 + (VCRAMbankBars[INSCREEN_RASTER] >> 4) * 0x400];
    const byte *cram = &cRSID_C64.IObankWR[CRAM_ADDRESS];
    int all = sw_refresh || cs != sw_prev_cs;
    for (int k = 0; k < SCREENHEIGHT; k++) {
        if (k == SCREENHEIGHT - 1)
            vram = &cRSID_C64.RAMbank[bank * 0x4000 + (VCRAMbankBars[ROW26_RASTER] >> 4) * 0x400 - SCREENWIDTH];
        for (int l = 0; l < SCREENWIDTH; l++) {
            int i = k * SCREENWIDTH + l;
            byte c = k == 24 ? Row25colors[l] : k == 25 ? (cs == 0 ? 0 : Row26colors[l]) : cram[i];
            byte v = vram[i];
            if (!all && !sw_dirty[i] && v == sw_prev_vram[i] && c == sw_prev_cram[i]) continue;
            sw_glyph(SIDEBORDER_WIDTH + l * 8, BORDER + k * CHARHEIGHT, &sw_charset[cs][v * 8], c & 15, 0);
            sw_prev_vram[i] = v; sw_prev_cram[i] = c; sw_dirty[i] = 0;
        }
    }
    sw_prev_cs = cs;
    /* the orderlist separators (row 26's top line, and the line under it) */
    Uint8 sep = (Uint8)(SW_SPR + (VICbankBars[INSCREEN_RASTER] != 3 ? 0xF : 0));
    sw_hline(BORDER + (SCREENHEIGHT - 1) * CHARHEIGHT, SIDEBORDER_WIDTH, SIDEBORDER_WIDTH + 320, sep);
    sw_hline(BORDER + SCREENHEIGHT * CHARHEIGHT, SIDEBORDER_WIDTH, SIDEBORDER_WIDTH + 320, sep);
}

/* 7 x-expanded sprites side by side (the last 2 bytes wide), 21 rows from y: drawBigSprites(). The orderlist's
 * (ghost) has the idle-graphics gap between its 4th and 5th pixel of every byte. A byte is drawn when it, the
 * colour or `all` changed; cache holds what was drawn. */
static void sw_draw_sprites(word addr, int y, int ghost, Uint8 col, Uint8 *cache, int all)
{
    for (int n = 0; n < 7; n++)
        for (int i = 0; i < SPRITE_HEIGHT; i++)
            for (int j = 0; j < (n == 6 ? 2 : 3); j++) {
                int o = n * 64 + i * 3 + j;
                byte b = cRSID_C64.RAMbank[addr + o];
                if (!all && cache[o] == b) continue;
                cache[o] = b;
                Uint32 c4 = col * 0x01010101u;
                Uint32 *p = (Uint32 *)(void *)(sw_fb + (y + i) * SW_STRIDE + SIDEBORDER_WIDTH + n * 48 + j * 16);
                p[0] = sw_dbl[b >> 4][0] & c4; p[1] = sw_dbl[b >> 4][1] & c4;
                p[2] = sw_dbl[b & 15][0] & c4; p[3] = sw_dbl[b & 15][1] & c4;
                if (ghost) { p[1] &= 0x00FFFFFFu; p[2] &= 0xFFFFFF00u; }
            }
}

/* The scope in the header (editor screen only): upstream's C64-UI oscilloscope, then new data is asked for. */
static void sw_draw_scope(void)
{
    enum { X = SIDEBORDER_WIDTH + 36 * 8 + 2 + 1, Y = 4, W = 22, H = 15, BOTTOM = 17 };
    for (int y = Y; y < Y + H; y++) sw_hline(y, X, X + W + 1, SW_SCOPEBG);
    for (int i = W - 1; i >= 0; i--) sw_fb[(BOTTOM - ((ScopeData[i] * H) >> 8)) * SW_STRIDE + X + i] = SW_SCOPE;
    ScopeDataCnt = 0;
}

/* The right border: every raster line's border colour, the main-volume bar over its top, the disk light. */
static void sw_draw_right(void)
{
    static byte warn;
    int x0 = SIDEBORDER_WIDTH + 320;
    for (int i = 0; i <= SW_H - CHARHEIGHT - 2; i++) {
        byte c = RasterBars[i + (FIRSTROW_RASTER - BORDER)] & 15;
        if (!sw_refresh && sw_bars[i] == c) continue;
        sw_bars[i] = c;
        sw_hline(i, x0, x0 + SIDEBORDER_WIDTH, (Uint8)(SW_SPR + c));
        if (i >= 3 && i < 19) sw_vol_sig = -1;              /* the volume bar is over this row */
    }
    int vol = cRSID.MainVolume, bg = vol || ((++warn) & 8) ? SW_VOLBG : SW_VOLWARN, sig = vol << 8 | bg;
    if (sig != sw_vol_sig) {
        int h = (vol * (16 - 4)) >> 8;
        for (int y = 3; y < 19; y++) sw_hline(y, x0 + 3, x0 + 7, (Uint8)bg);
        for (int y = 19 - h - 2; y < 19 - 2; y++) sw_hline(y, x0 + 4, x0 + 6, SW_VOLSCALE);
        sw_vol_sig = sig;
    }
    Uint8 light = (Uint8)(SW_SPR + (ProgressSig != sw_prev_progress && SpritEnaBars[INSCREEN_RASTER] == 0 ? ProgressSig & 15 : 0));
    for (int y = SW_H - CHARHEIGHT - 1; y < SW_H - 1; y++) sw_hline(y, x0 + 1, x0 + SIDEBORDER_WIDTH - 1, light);
    sw_prev_progress = ProgressSig;
}

/* The cursor sprite (displayScreen()'s last part): in the screen, or over the orderlist when its Y is above the
 * top border's sprites. Returns its rectangle; draws it when `draw`. */
static void sw_cursor(int draw, int *rx, int *ry, int *rw, int *rh)
{
    byte *io = cRSID_C64.IObankWR;
    int cx = ((io[0xD010] & 1) ? 256 : 0) + io[0xD000] - FIRSTCOLUMN_RASTER, cy = io[0xD001] - (FIRSTROW_RASTER - BORDER);
    word addr; byte col, on, wide;
    CursorX = (byte)(cx / 8); CursorY = (byte)(cy / 8 - 1);
    if (io[0xD001] >= FIRSTROW_RASTER - SPRITE_HEIGHT) {
        addr = CURSORSPRITE_ADDRESS; col = SpriteColBars[INSCREEN_RASTER];
        on = SpritEnaBars[INSCREEN_RASTER] & 1; wide = SpriteWidthBars[INSCREEN_RASTER] & 1;
    } else {
        addr = (word)(cRSID_C64.RAMbank[0x7F8] * 64); col = SpriteColBars[ORDERLIST_RASTER];
        on = SpritEnaBars[ORDERLIST_RASTER] & 1; wide = 0;
    }
    int x = SIDEBORDER_WIDTH + cx, y = cy + 1;
    if (y < 0) y += SW_H + 2;
    *rw = 0; *rh = 0; *rx = x; *ry = y;
    if (x < 0 || y < 0 || !on || y >= SW_H) return;
    int bytes = x < SIDEBORDER_WIDTH + 320 - 24 ? 3 : (SIDEBORDER_WIDTH + 320 - x) / 8;
    int pw = wide ? 2 : 1, h = y + SPRITE_HEIGHT > SW_H ? SW_H - y : SPRITE_HEIGHT;
    *rw = bytes * 8 * pw; *rh = h;
    if (!draw) return;
    Uint8 c = (Uint8)(SW_SPR + (col & 15));
    for (int i = 0; i < h; i++)
        for (int j = 0; j < bytes; j++) {
            byte b = cRSID_C64.RAMbank[addr + i * 3 + j];
            for (int k = 0; k < 8; k++)
                if (b & (0x80 >> k)) for (int q = 0; q < pw; q++) sw_fb[(y + i) * SW_STRIDE + x + (j * 8 + k) * pw + q] = c;
        }
}

/* Mark what a rectangle covers to be drawn again: text cells, or the whole header / orderlist band. */
static void sw_uncover(int x, int y, int w, int h, int *header, int *bottom)
{
    if (w <= 0 || h <= 0) return;
    if (y < BORDER) *header = 1;
    if (y + h > SW_BOTTOM_Y - 2) *bottom = 1;
    for (int r = (y - BORDER) / CHARHEIGHT; r <= (y + h - 1 - BORDER) / CHARHEIGHT; r++)
        for (int c = (x - SIDEBORDER_WIDTH) / 8; c <= (x + w - 1 - SIDEBORDER_WIDTH) / 8; c++)
            if (r >= 0 && r < SCREENHEIGHT && c >= 0 && c < SCREENWIDTH) sw_dirty[r * SCREENWIDTH + c] = 1;
}

static const char sw_exit_text[] = "                                        \n"
                                   " ************************************** \n"
                                   " * DO YOU REALLY WANT TO EXIT?  (Y/N) * \n"
                                   " ************************************** \n"
                                   "                                        ";

/* SIDwizard.c's exit dialog: drawString() at row 13 in the PC host's own ASCII charset (buttoncharset.h). */
static void sw_draw_dialog(void)
{
    int x = 0, y = SCREENHEIGHT / 2;
    for (const char *s = sw_exit_text; *s; s++) {
        if (*s == '\n') { y++; x = 0; continue; }
        sw_glyph(SIDEBORDER_WIDTH + x * 8, y * CHARHEIGHT, &charset[(byte)*s * 8], SW_DLGFG, SW_DLGBG);
        x++;
    }
}

static void sw_video_frame(void)
{
    int nx, ny, nw, nh, header = sw_refresh, bottom = sw_refresh;
    if (sw_dialog) { if (sw_refresh) { sw_draw_dialog(); sw_refresh = 0; } return; }
    sw_cursor(0, &nx, &ny, &nw, &nh);
    sw_uncover(sw_cur.x, sw_cur.y, sw_cur.w, sw_cur.h, &header, &bottom);
    sw_uncover(nx, ny, nw, nh, &header, &bottom);
    Uint8 col = (Uint8)(SpritEnaBars[0] != 0 ? SW_SPR + (cRSID_C64.IObankWR[0xD02A] & 15) : 0);
    if (header) { sw_hline(0, 0, SW_W, 0); sw_hline(BORDER - 1, 0, SW_W, 0); }
    sw_draw_sprites(TOPSPRITE_ADDRESS, 1, 0, col, sw_top, header || col != sw_top_col);
    sw_draw_sprites(BOTTOMSPRITE_ADDRESS, SW_BOTTOM_Y, 1, col, sw_bottom, bottom || col != sw_bottom_col);
    sw_top_col = sw_bottom_col = col;
    if (SpritEnaBars[0] != 0) sw_draw_scope();
    sw_draw_text();
    sw_draw_right();
    sw_cursor(1, &nx, &ny, &nw, &nh);
    sw_cur.x = nx; sw_cur.y = ny; sw_cur.w = nw; sw_cur.h = nh;
    sw_refresh = 0;
}
