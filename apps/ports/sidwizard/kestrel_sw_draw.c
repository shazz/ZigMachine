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
            sw_prev_vram[i] = v; sw_prev_cram[i] = c; sw_dirty[i] = 0; sw_drawn[i] = sw_frame_no;
        }
    }
    sw_prev_cs = cs;
    /* the orderlist separators (row 26's top line, and the line under it): again when their colour changed, a
     * row-26 cell was drawn over the first, or the cursor was or is over them (sw_sep_dirty) */
    static Uint8 sep_drawn = 0xFF;
    Uint8 sep = (Uint8)(SW_SPR + (VICbankBars[INSCREEN_RASTER] != 3 ? 0xF : 0));
    int row26 = 0;
    for (int l = 0; l < SCREENWIDTH && !row26; l++) row26 = sw_drawn[(SCREENHEIGHT - 1) * SCREENWIDTH + l] == sw_frame_no;
    if (sep != sep_drawn || row26 || sw_sep_dirty) sw_hline(BORDER + (SCREENHEIGHT - 1) * CHARHEIGHT, SIDEBORDER_WIDTH, SIDEBORDER_WIDTH + 320, sep);
    if (sep != sep_drawn || sw_sep_dirty) sw_hline(BORDER + SCREENHEIGHT * CHARHEIGHT, SIDEBORDER_WIDTH, SIDEBORDER_WIDTH + 320, sep);
    sep_drawn = sep;
}

/* 7 x-expanded sprites side by side (the last 2 bytes wide), 21 rows from y: drawBigSprites(). The orderlist's
 * (ghost) has the idle-graphics gap between its 4th and 5th pixel of every byte. A byte is drawn when it, the
 * colour or `all` changed; cache holds what was drawn. */
static int sw_force_lo = 1 << 30, sw_force_hi;  /* picture rows the cursor was or is over: drawn again */

static void sw_draw_sprites(word addr, int y, int ghost, Uint8 col, Uint8 *cache, int all)
{
    for (int n = 0; n < 7; n++)
        for (int i = 0; i < SPRITE_HEIGHT; i++)
            for (int j = 0; j < (n == 6 ? 2 : 3); j++) {
                int o = n * 64 + i * 3 + j;
                byte b = cRSID_C64.RAMbank[addr + o];
                if (!all && cache[o] == b && (y + i < sw_force_lo || y + i >= sw_force_hi)) continue;
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
    static Uint8 light_drawn = 0xFF;
    Uint8 light = (Uint8)(SW_SPR + (ProgressSig != sw_prev_progress && SpritEnaBars[INSCREEN_RASTER] == 0 ? ProgressSig & 15 : 0));
    if (light != light_drawn || sw_refresh)
        for (int y = SW_H - CHARHEIGHT - 1; y < SW_H - 1; y++) sw_hline(y, x0 + 1, x0 + SIDEBORDER_WIDTH - 1, light);
    light_drawn = light;
    sw_prev_progress = ProgressSig;
}

/* The cursor sprite (displayScreen()'s last part): in the screen, or over the orderlist when its Y is above the
 * top border's sprites. Returns its rectangle; draws it when `draw`. */
static Uint8 sw_cur_sig[96], sw_cur_sig_new[96];   /* the cursor as drawn: rectangle, colour, its 63 bytes */

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
    if (x < 0 || y < 0 || !on || y >= SW_H) { if (!draw) memset(sw_cur_sig_new, 0, sizeof sw_cur_sig_new); return; }
    int bytes = x < SIDEBORDER_WIDTH + 320 - 24 ? 3 : (SIDEBORDER_WIDTH + 320 - x) / 8;
    int pw = wide ? 2 : 1, h = y + SPRITE_HEIGHT > SW_H ? SW_H - y : SPRITE_HEIGHT;
    /* the rectangle is the rows the sprite has pixels in (a cursor box is a few rows of its 21) */
    int top = -1, bot = -1;
    for (int i = 0; i < h; i++)
        for (int j = 0; j < bytes; j++)
            if (cRSID_C64.RAMbank[addr + i * 3 + j]) { if (top < 0) top = i; bot = i; }
    *rw = top < 0 ? 0 : bytes * 8 * pw; *rh = top < 0 ? 0 : bot - top + 1; *ry = y + (top < 0 ? 0 : top);
    if (!draw) {
        int head[5] = { x, y, *rw, *rh, col & 15 };
        memcpy(sw_cur_sig_new, head, sizeof head);
        memcpy(sw_cur_sig_new + sizeof head, &cRSID_C64.RAMbank[addr], 63);
        return;
    }
    Uint8 c = (Uint8)(SW_SPR + (col & 15));
    for (int i = 0; i < h; i++)
        for (int j = 0; j < bytes; j++) {
            byte b = cRSID_C64.RAMbank[addr + i * 3 + j];
            for (int k = 0; k < 8; k++)
                if (b & (0x80 >> k)) for (int q = 0; q < pw; q++) sw_fb[(y + i) * SW_STRIDE + x + (j * 8 + k) * pw + q] = c;
        }
}

/* Mark what a rectangle covers to be drawn again: text cells, and the header / orderlist rows under it (the
 * black lines at 0 and BORDER - 1 too: `header`). */
static void sw_uncover(int x, int y, int w, int h, int *header, int *bottom)
{
    (void)bottom;
    if (w <= 0 || h <= 0) return;
    if (y < BORDER || y + h > SW_BOTTOM_Y - 2) {
        if (y < sw_force_lo) sw_force_lo = y;
        if (y + h > sw_force_hi) sw_force_hi = y + h;
    }
    if (y <= 0 || (y <= BORDER - 1 && y + h > BORDER - 1)) *header = 1;
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

/* Does a rectangle reach the header, the orderlist, or the separator lines between the text and the orderlist? */
static int sw_off_text(int y, int h) { return h > 0 && (y < BORDER || y + h > BORDER + (SCREENHEIGHT - 1) * CHARHEIGHT); }

/* Any text cell under a rectangle drawn this frame (the cursor must go back over it). */
static int sw_cells_drawn(int x, int y, int w, int h)
{
    if (w <= 0 || h <= 0) return 0;
    for (int r = (y - BORDER) / CHARHEIGHT; r <= (y + h - 1 - BORDER) / CHARHEIGHT; r++)
        for (int c = (x - SIDEBORDER_WIDTH) / 8; c <= (x + w - 1 - SIDEBORDER_WIDTH) / 8; c++)
            if (r >= 0 && r < SCREENHEIGHT && c >= 0 && c < SCREENWIDTH && sw_drawn[r * SCREENWIDTH + c] == sw_frame_no) return 1;
    return 0;
}

static void sw_video_frame(void)
{
    int nx, ny, nw, nh, header = sw_refresh, bottom = sw_refresh;
    if (sw_dialog) { if (sw_refresh) { sw_draw_dialog(); sw_refresh = 0; } return; }
    sw_frame_no++;
    sw_cursor(0, &nx, &ny, &nw, &nh);
    /* A cursor that has not moved, changed or blinked, in the text area, is left where it is (the planner then
     * finds those lines unchanged); else what it covered is drawn again, then it. */
    int still = !sw_refresh && !memcmp(sw_cur_sig, sw_cur_sig_new, sizeof sw_cur_sig)
        && !sw_off_text(sw_cur.y, sw_cur.h) && !sw_off_text(ny, nh);
    sw_sep_dirty = sw_refresh || sw_off_text(sw_cur.y, sw_cur.h) || sw_off_text(ny, nh);
    if (!still) {
        sw_uncover(sw_cur.x, sw_cur.y, sw_cur.w, sw_cur.h, &header, &bottom);
        sw_uncover(nx, ny, nw, nh, &header, &bottom);
    }
    Uint8 col = (Uint8)(SpritEnaBars[0] != 0 ? SW_SPR + (cRSID_C64.IObankWR[0xD02A] & 15) : 0);
    if (header) { sw_hline(0, 0, SW_W, 0); sw_hline(BORDER - 1, 0, SW_W, 0); }
    sw_draw_sprites(TOPSPRITE_ADDRESS, 1, 0, col, sw_top, sw_refresh || col != sw_top_col);
    sw_draw_sprites(BOTTOMSPRITE_ADDRESS, SW_BOTTOM_Y, 1, col, sw_bottom, sw_refresh || col != sw_bottom_col);
    sw_force_lo = 1 << 30; sw_force_hi = 0;
    sw_top_col = sw_bottom_col = col;
    if (SpritEnaBars[0] != 0 && !SW_SID_ON_BARD) sw_draw_scope();   /* the samples are the sound side's now */
    sw_draw_text();
    sw_draw_right();
    if (!still || sw_cells_drawn(nx, ny, nw, nh)) sw_cursor(1, &nx, &ny, &nw, &nh);
    memcpy(sw_cur_sig, sw_cur_sig_new, sizeof sw_cur_sig);
    sw_cur.x = nx; sw_cur.y = ny; sw_cur.w = nw; sw_cur.h = nh;
    sw_refresh = 0;
}
