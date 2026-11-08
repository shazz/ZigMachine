/* The cart's input exports as SID-Wizard's PC host saw SDL 1.2 (included by kestrel_sw.c, after upstream's
 * host/keyboard.c and host/mouse.c).
 *
 * Upstream's keyboard.c reads SDL_GetKeyState() (SDL 1.2 key symbols: what the key means, so Shift+3 is still
 * SDLK_3 with Shift held) and the X11 keycode of the last key pressed (where the key is: the piano keys and the
 * '-' '=' '[' ']' '\' positional keys). The machine sends what was typed (sealed-loader.js: '#' for Shift+3, '3'
 * when it comes up after Shift), so a typed character is folded back to its US key, which gives both.
 * The keys SIDwizard.c's own event loop handled before the C64 sees anything are handled here too: Shift+F8 the
 * exit dialog, Shift+F7/F9 reset the editor, F11/F12 and Shift+Up/Down the main volume. */

static Uint8 sw_keys[SDLK_LAST + 1];
Uint8 *SDL_GetKeyState(int *numkeys) { if (numkeys) *numkeys = SDLK_LAST; return sw_keys; }

/* US keyboard rows: character -> X11 keycode (evdev + 8), and the shifted characters -> their key. */
static const char sw_row1[] = "1234567890-=", sw_row2[] = "qwertyuiop[]", sw_row3[] = "asdfghjkl;'`", sw_row4[] = "zxcvbnm,./";
static const char sw_shifted[] = "!@#$%^&*()_+{}:\"<>?~|", sw_unshifted[] = "1234567890-=[];',./`\\";

static int sw_x11_of(int c)
{
    const char *p;
    if ((p = strchr(sw_row1, c)) && c) return 10 + (int)(p - sw_row1);
    if ((p = strchr(sw_row2, c)) && c) return 24 + (int)(p - sw_row2);
    if ((p = strchr(sw_row3, c)) && c) return 38 + (int)(p - sw_row3);
    if ((p = strchr(sw_row4, c)) && c) return 52 + (int)(p - sw_row4);
    if (c == '\\') return 51;
    if (c == ' ') return 65;
    return 0;
}

/* A host key code (sealed-loader.js KEY_CODES / MOD_CODES, or a typed character) -> SDL 1.2 symbol + X11 keycode;
 * 0 = no key SID-Wizard knows. Alt (0xE013, a toggle on the host) and AltGr are left out: upstream ignores every
 * key while an Alt is held (Alt+Tab). */
static int sw_sym_of(Uint32 cp, int *x11)
{
    static const struct { Uint32 code; int sym, x11; } special[] = {
        { 8, SDLK_BACKSPACE, 22 }, { 13, SDLK_RETURN, 36 }, { 0xE00C, SDLK_DELETE, 119 }, { 0xE00B, SDLK_INSERT, 118 },
        { 0xE012, SDLK_ESCAPE, 9 }, { 0xE014, SDLK_LCTRL, 37 }, { 0xE015, SDLK_LSHIFT, 50 }, { 0xE016, SDLK_RCTRL, 105 },
        { 0xE017, SDLK_RSHIFT, 62 }, { 0xE019, SDLK_TAB, 23 }, { 0xE01A, SDLK_HOME, 110 }, { 0xE01B, SDLK_END, 115 },
        { 0xE01C, SDLK_PAGEUP, 112 }, { 0xE01D, SDLK_PAGEDOWN, 117 }, { 0xE01E, SDLK_F11, 95 }, { 0xE01F, SDLK_F12, 96 },
    };
    *x11 = 0;
    for (unsigned i = 0; i < sizeof special / sizeof special[0]; i++)
        if (special[i].code == cp) { *x11 = special[i].x11; return special[i].sym; }
    if (cp >= 0xE001 && cp <= 0xE00A) { *x11 = 67 + (int)(cp - 0xE001); return SDLK_F1 + (int)(cp - 0xE001); }
    if (cp < 32 || cp >= 127) return 0;
    int c = (int)cp;
    if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    const char *s = strchr(sw_shifted, c);
    if (s) c = sw_unshifted[s - sw_shifted];
    *x11 = sw_x11_of(c);
    return c;
}

static int sw_shift_held(void) { return sw_keys[SDLK_LSHIFT] || sw_keys[SDLK_RSHIFT]; }

/* SIDwizard.c's SDL_KEYDOWN switch (its main loop): what the PC host does itself. 1 = the key is used up. */
static int sw_host_key(int sym)
{
    if (sw_exit_dialog == 1) {                  /* "DO YOU REALLY WANT TO EXIT? (Y/N)" */
        if (sym == SDLK_y) { kestrel_quit(); return 1; }
        sw_exit_dialog = 2;                     /* any other key: closes on its release */
        return 1;
    }
    if (sw_exit_dialog) return 1;
    switch (sym) {
    case SDLK_F9: case SDLK_F7:
        if (sw_shift_held() && ArgLoading == 0 && !sw_startup_menu) sw_reset_editor();
        return 0;
    case SDLK_F8:
        if (sw_shift_held() && ArgLoading == 0) { sw_exit_dialog = 1; cRSID.Paused = 1; sw_video_dialog(1); return 1; }
        return 0;
    case SDLK_UP: if (sw_shift_held()) volumeUp(); return 0;
    case SDLK_DOWN: if (sw_shift_held()) volumeDown(); return 0;
    case SDLK_F12: volumeUp(); return 0;
    case SDLK_F11: volumeDown(); return 0;
    }
    return 0;
}

static void sw_key_down(int sym, int x11)
{
    if (sw_host_key(sym)) return;
    sw_keys[sym] = 1;
    ScanCode = (byte)x11;
}

static void sw_key_up(int sym, int x11)
{
    if (sw_exit_dialog == 2) { sw_exit_dialog = 0; cRSID.Paused = 0; sw_video_dialog(0); }
    sw_keys[sym] = 0;
    if (ScanCode == x11) ScanCode = 0;
}

__attribute__((export_name("ownsKeyboard"))) int ownsKeyboard(void) { return 1; }
__attribute__((export_name("drawsOwnPointer"))) int drawsOwnPointer(void) { return 0; }

__attribute__((export_name("key"))) void key(Uint32 cp)
{
    int x11, sym = sw_sym_of(cp, &x11);
    if (sym) sw_key_down(sym, x11);
}

__attribute__((export_name("keyUp"))) void keyUp(Uint32 cp)
{
    int x11, sym = sw_sym_of(cp, &x11);
    if (sym) sw_key_up(sym, x11);
}

static const int sw_arrow_sym[4] = { SDLK_UP, SDLK_DOWN, SDLK_LEFT, SDLK_RIGHT }, sw_arrow_x11[4] = { 111, 116, 113, 114 };
__attribute__((export_name("input"))) void input(Uint32 dir) { if (dir < 4) sw_key_down(sw_arrow_sym[dir], sw_arrow_x11[dir]); }
__attribute__((export_name("inputRelease"))) void inputRelease(Uint32 dir) { if (dir < 4) sw_key_up(sw_arrow_sym[dir], sw_arrow_x11[dir]); }

/* The pointer: SIDwizard.c's SDL_MOUSEBUTTONDOWN at zoom 1 (character cell under the click), handled by upstream's
 * mouse.c as key sequences. Host coordinates are the 320x200 window's, x doubled; the window sits at (40,40) of
 * the 400x280 plane and the C64 picture at SW_OX,SW_OY (kestrel_sw_video.c). */
__attribute__((export_name("pointer"))) void pointer(int x, int y, Uint32 b)
{
    static Uint32 prev;
    int fx = x / 2 + 40 - SW_OX, fy = y + 40 - SW_OY;
    if ((b & 5) && !(prev & 5) && !sw_exit_dialog) {
        MouseClickX = (signed char)((fx - SIDEBORDER_WIDTH) >> 3);
        MouseClickY = (signed char)((fy - BORDER) / CHARHEIGHT);
        if (VICbankBars[INSCREEN_RASTER] != 3) { MouseClicked = 1; MouseKeyPressDurationCnt = MOUSEKEYPRESS_DURATOIN; FirstPress = 1; }
    }
    prev = b;
}
