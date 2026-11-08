#define KEY_AMOUNT 64
#define SDLK_DUMMY 0
#define SHIFTED_KEY_DELAY 6
#if ( defined(_LINUX) || defined(LINUX) )
 #define OS_SCANCODESUB_X11 0
 #define OS_SCANCODESUB_FBCON 8
#elif ( defined(_WINDOWS) || defined(WINDOWS) )
 #define OS_SCANCODESUB 8
#endif


enum { C64_KEYTABLE_ROWS = 8, C64_KEYTABLE_COLUMNS = 8, C64_KEYTABLE_LENGTH = (C64_KEYTABLE_ROWS * C64_KEYTABLE_COLUMNS),
       C64_LEFTSHIFT_ROW = 1, C64_LEFTSHIFT_COLUMN = 7, C64_RIGHTSHIFT_ROW = 6, C64_RIGHTSHIFT_COLUMN = 4, C64_CBMKEY_ROW = 7 };


#if (ENABLED_SDL_EVENTS) //(ENABLED_SDL)

#if (defined(_LINUX) || defined(LINUX))
 static const int SDLscanCodeToC64keyX11[] = { // X11/XTERM //hardware and OS dependent?!
 //                                         - =+
 //                                        20 21
  0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0, 0,0,0, //0..23
 //    Q    W   E    R    T    Y    U    I    O    P    [    ]         A    S    D    F    G    H    J    K    L  ;->: '     \   Z    X    C    V    B    N    M  COMMA DOT //note-keys
 //   24,  25,  26,  27,  28,  29,  30,  31,  32,  33,  0,   0,  0,0, 38,  39,  40,  41,  42,  43,  44,  45,  46,  47, 0,0,0,0, 52,  53,  54,  55,  56,  57,  58,  59,  60 //scancodes
     0x3E,0x09,0x0E,0x11,0x16,0x19,0x1E,0x21,0x26,0x29,0x2E,0x31,0,0,0x0A,0x0D,0x12,0x15,0x1A,0x1D,0x22,0x25,0x2A,0x2D,0,0,0,0,0x0C,0x17,0x14,0x1F,0x1C,0x27,0x24,0x2F,0x2C,0,0,0
 };
 static const int SDLscanCodeToC64keyFBCON[] = { //different scancodes for the linux character-based console (matches Windows codes below, Sigh!) //hardware and OS dependent?!
 //                         - =+                 //scancodes can be found in SDL source-code: scr/video/fbcon/SDL_fbkeys.h
 //                        12 13
  0, 0,0,0,0,0,0,0,0,0,0,0, 0, 0,0,0, //0..15
 //    Q    W   E    R    T    Y    U    I    O    P    [    ]         A    S    D    F    G    H    J    K    L  ;->: '     \   Z    X    C    V    B    N    M  COMMA DOT //note-keys
 //   16,  17,  18,  19,  20,  21,  22,  23,  24,  25, 26,  27,  0,0, 30,  31,  32,  33,  34,  35,  36,  37,  38,  39,40,0,0,43,44,  45,  46,  47,  48,  49,  50,  51,  52 //scancodes
     0x3E,0x09,0x0E,0x11,0x16,0x19,0x1E,0x21,0x26,0x29,0x2E,0x31,0,0,0x0A,0x0D,0x12,0x15,0x1A,0x1D,0x22,0x25,0x2A,0x2D,0,0,0,0,0x0C,0x17,0x14,0x1F,0x1C,0x27,0x24,0x2F,0x2C,0,0,0,0,0,0,0,0, 0,0,0
 };
 static const int* SDLscanCodeToC64keyNonX11 = SDLscanCodeToC64keyFBCON;
 static const int* SDLscanCodeToC64key = SDLscanCodeToC64keyX11; //default value
 char OS_SCANCODESUB = OS_SCANCODESUB_X11;

#elif ( defined(_WINDOWS) || defined(WINDOWS) )
 static const int SDLscanCodeToC64key[] = { //hardware and OS dependent?!
  0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, //0..15
 //    Q    W    E    R    T    Y    U    I    O    P   [    ]         A    S    D    F    G    H    J    K    L  ;->: '     \   Z   X    C    V    B    N    M  COMMA DOT //note-keys
 //   16,  17,  18,  19,  20,  21,  22,  23,  24,  25, 26,  27,  0,0, 30,  31,  32,  33,  34,  35,  36,  37,  38,  39, 0,0,0,0, 44, 45,  46,  47,  48,  49,  50,  51,  52  //scancodes
     0x3E,0x09,0x0E,0x11,0x16,0x19,0x1E,0x21,0x26,0x29,0x2E,0x31,0,0,0x0A,0x0D,0x12,0x15,0x1A,0x1D,0x22,0x25,0x2A,0x2D,0,0,0,0,0x0C,0x17,0x14,0x1F,0x1C,0x27,0x24,0x2F,0x2C,0,0,0,0,0,0,0,0, 0,0,0
 };
#endif

static const int SDLKeyToC64key [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = {
//      0    1     2    3    4    5   6    7 (DC00/DC01)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
    { SDLK_DELETE, SDLK_RETURN, SDLK_RIGHT, SDLK_F7, SDLK_F1/*|SDL_KEY_NONSHIFTED*/, SDLK_F3/*|SDL_KEY_NONSHIFTED*/, SDLK_F5, SDLK_DOWN },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
    { SDLK_3, SDLK_w, SDLK_a, SDLK_4, SDLK_z, SDLK_s, SDLK_e, SDLK_LSHIFT },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
    { SDLK_5, SDLK_r, SDLK_d, SDLK_6, SDLK_c, SDLK_f, SDLK_t, SDLK_x },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
    { SDLK_7, SDLK_y, SDLK_g, SDLK_8, SDLK_b, SDLK_h, SDLK_u, SDLK_v },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
    { SDLK_9, SDLK_i, SDLK_j, SDLK_0, SDLK_m, SDLK_k, SDLK_o, SDLK_n },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
    { SDLK_PLUS, SDLK_p, SDLK_l, SDLK_MINUS, SDLK_PERIOD, SDLK_SEMICOLON, SDLK_AT, SDLK_COMMA },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { SDLK_INSERT, SDLK_ASTERISK, SDLK_DUMMY, SDLK_HOME, SDLK_RSHIFT, SDLK_EQUALS, SDLK_PAGEDOWN, SDLK_SLASH },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
    { SDLK_1, SDLK_BACKQUOTE, SDLK_TAB , SDLK_2, SDLK_SPACE, SDLK_LCTRL, SDLK_q, SDLK_PAUSE } //SDLK_ESCAPE
};

static const int SDLKeyToC64key_Alternative [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = { //extra PC-keyboard keys to expand C64 key-capabilities
//      0    1     2    3    4    5   6    7 (DC00/DC01)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
    { SDLK_BACKSPACE, /*SDLK_OR_SIGN*//*SDLK_BACKSLASH*/SDLK_KP_ENTER, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
    { SDLK_KP3, SDLK_DUMMY, SDLK_DUMMY, SDLK_KP4, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
    { SDLK_KP5, SDLK_DUMMY, SDLK_DUMMY, SDLK_KP6, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
    { SDLK_KP7, SDLK_DUMMY, SDLK_DUMMY, SDLK_KP8, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
    { SDLK_KP9, SDLK_DUMMY, SDLK_DUMMY, SDLK_KP0, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
    { SDLK_KP_PLUS, SDLK_DUMMY, SDLK_DUMMY, SDLK_KP_MINUS, /*SDLK_END*/SDLK_DUMMY, SDLK_COLON, SDLK_DUMMY, /*SDLK_HOME*/SDLK_DUMMY },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_QUOTE, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
    { SDLK_KP1, SDLK_END, SDLK_DUMMY, SDLK_KP2, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_ESCAPE },
};

static const int SDLKeyToC64key_Shift [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = { //extra PC-keyboard keys to expand C64 key-capabilities
//      0    1     2    3    4    5   6    7 (DC00/DC01)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
    { SDLK_DUMMY   , /*SDLK_BACKSLASH*/SDLK_DUMMY , SDLK_LEFT, SDLK_F8, /*SDLK_DUMMY*/SDLK_F2, /*SDLK_DUMMY*/SDLK_F4, SDLK_F6, SDLK_UP },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_PAGEUP, SDLK_DUMMY },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
};
static const int SDLKeyToC64key_Shift_SDLshiftedKeyExtras [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = {
//      0    1     2    3    4    5   6    7 (DC00/DC01) //As with TUI, for consistency between TUI & SDL-UI, e.g. give Shift+\ the same function as Shift+Enter
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
    { SDLK_DUMMY, SDLK_BACKSLASH/*SDLK_DUMMY*/, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
};

static const int SDLKeyToC64key_CBMkey [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = { //extra PC-keyboard keys to expand C64 key-capabilities
//      0    1     2    3    4    5   6    7 (DC00/DC01)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, /*SDLK_SHIFT_F1*/SDLK_DUMMY, /*SDLK_SHIFT_F3*/SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
    { SDLK_KP_MULTIPLY, SDLK_DUMMY, SDLK_DUMMY, SDLK_KP_DIVIDE, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
};
static const int SDLKeyToC64key_CBM_SDLshiftedKeyExtras [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = {
//      0    1     2    3    4    5   6    7 (DC00/DC01) //As with TUI, for consistency between TUI & GUI, give Shift+F1/F3 the same function as Ctrl+F1/F3
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_F1/*with Shift*/, SDLK_F3/*with Shift*/, SDLK_DUMMY, SDLK_DUMMY },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_F6/*paging on old console:SDLK_PAGEUP*/, SDLK_DUMMY, SDLK_DUMMY, SDLK_F5/*paging on old console:SDLK_PAGEDOWN*/ },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
};
static const int SDLKeyToC64key_CBM_SDLCtrlkeyExtras [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = {
//      0    1     2    3    4    5   6    7 (DC00/DC01) //As with TUI, for consistency between TUI & SDL-UI, give Ctrl+Home/End the same function as Ctrl+./,
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY/*SDLK_F1*//*with Ctrl*/, SDLK_DUMMY/*SDLK_F3*//*with Ctrl*/, SDLK_DUMMY, SDLK_DUMMY },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_u/*SDLK_DUMMY*/, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_END, SDLK_DUMMY, SDLK_DUMMY, SDLK_HOME },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
};

static const int SDLKeyToC64key_Shift_plus_CBM_SDLshiftedKeyExtras [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = {
//      0    1     2    3    4    5   6    7 (DC00/DC01) //As with TUI, for consistency between TUI & SDL-UI, give Shift+F2/F4 the same function as Ctrl+F2/F4 (Shift+Ctrl+F1/F3)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_F2/*with Shift*/, SDLK_F4/*with Shift*/, SDLK_DUMMY, SDLK_DUMMY },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
    { SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY, SDLK_DUMMY },
};

#endif //(ENABLED_SDL_EVENTS)


#if (ENABLED_TUI_KEYS) //(ENABLED_NCURSES) //ENABLED_TUI

enum { /*NCURSES_KEY_NONE = -1,*/ NCURSES_KEY_DUMMY = -2, KEY_DUMMY=NCURSES_KEY_DUMMY, NCURSES_KEYCODE_ESC = 27, //NCURSES_KEYCODE_ALT = NCURSES_KEYCODE_ESC, //ncurses gives this code but couldn't find a symbol for it in cruses.h
       KEY_BACKSPACE_ALTERNATIVE=0x7F, //on some terminals this is backspace without ctrl
       NCURSES_KEYCODE_SHIFT__Fx=(KEY_F0+12), NCURSES_KEYCODE_SHIFT_F8 = (NCURSES_KEYCODE_SHIFT__Fx+8), NCURSES_KEYCODE_SHIFT_F10 = (NCURSES_KEYCODE_SHIFT__Fx+10),
        NCURSES_KEYCODE_SHIFT_F9 = (NCURSES_KEYCODE_SHIFT__Fx+9), NCURSES_KEYCODE_SHIFT_F7 = (NCURSES_KEYCODE_SHIFT__Fx+7), //On Linux/fbcon terminal Shift only modifies F1..F8
       NCURSES_KEYCODE_CTRL__Fx=(KEY_F0+12*2), NCURSES_KEYCODE_CTRL_F10 = (NCURSES_KEYCODE_CTRL__Fx+10), NCURSES_KEYCODE_CTRL_F8 = (NCURSES_KEYCODE_CTRL__Fx+8),
       NCURSES_KEYCODE_CTRL__LETTERS = -('a'-1), TUI_CTRL = NCURSES_KEYCODE_CTRL__LETTERS, //NCURSES_KEYCODE_CTRL_C = (TUI_CTRL + 'c'),
       NCURSES_KEYCODE_CTRL_4 = 0x1C, NCURSES_KEYCODE_CTRL_5 = 0x1D, NCURSES_KEYCODE_CTRL_6 = 0x1E, NCURSES_KEYCODE_CTRL_7 = 0x1F,
       NCURSES_KEYCODE_CTRL_MINUS = NCURSES_KEYCODE_CTRL_7,
       NCURSES_KEYCODE_CTRL_SLASH = NCURSES_KEYCODE_CTRL_MINUS, NCURSES_KEYCODE_CTRL_BACKSLASH = NCURSES_KEYCODE_CTRL_4,
       NCURSES_KEYCODE_CTRL_2 = 0, NCURSES_KEYCODE_CTRL_SPACE = NCURSES_KEYCODE_CTRL_2, NCURSES_KEYCODE_CTRL_TILDE = NCURSES_KEYCODE_CTRL_2, //NCURSES_KEYCODE_CTRL_SHIFT_TILDE=NCURSES_KEYCODE_CTRL_6,
       NCURSES_KEYCODE_CTRL_3 = NCURSES_KEYCODE_ESC /*0x1B*/, NCURSES_KEYCODE_CTRL_LBRACKET = NCURSES_KEYCODE_ESC /*0x1B*/,
       NCURSES_KEYCODE_CTRL_8 = KEY_BACKSPACE, NCURSES_KEYCODE_CTRL_RBRACKET = NCURSES_KEYCODE_CTRL_5 /*0x1D*/,
       NCURSES_KEYCODE_CTRL_OR_SIGN = NCURSES_KEYCODE_CTRL_4,
       //NCURSES_KEYCODE_MOD__Fx=(KEY_F0+12*3), NCURSES_KEYCODE_MOD_F10 = (NCURSES_KEYCODE_MOD__Fx+10),
       //NCURSES_KEYCODE_ALT__Fx=(KEY_F0+12*4), NCURSES_KEYCODE_ALT_F9 = (NCURSES_KEYCODE_ALT__Fx+9) //'Meta'? //Not suppored/relevant on Linux/fbcon terminal (where Alt+Fx changes terminals)
       //these values seem terminal-emulator implementation-dependent (off by 1 on old xterm that supports it, linux/fbcon doesn't support them, values are out of curses.h documented 0..511 range):
       NCURSES_XTERM_DEPENDENT_KEYS = 0x200,
       NCURSES_KEYCODE_CTRL_LEFT = /*new terminals:*/0x221 /*old terminals: 0x222*/, NCURSES_KEYCODE_CTRL_RIGHT = /*new terminals:*/0x230 /*old terminals: 0x231*/,
       NCURSES_KEYCODE_CTRL_UP = /*new terminals:*/0x236 /*old terminals: 0x237*/, NCURSES_KEYCODE_CTRL_DOWN = /*new terminals:*/0x20D /*old terminals: 0x20E*/,
       NCURSES_KEYCODE_CTRL_HOME = /*new terminals:*/0x217/*old terminals: 0x218*/, NCURSES_KEYCODE_CTRL_END = /*new terminals:*/0x212/*old terminals: 0x213*/,
       NCURSES_KEYCODE_CTRL_PAGEUP=0x22C, NCURSES_KEYCODE_CTRL_PAGEDOWN=0x227
};
enum { NCURSES_KEYCODE_F1=KEY_F(1)/*265*/, NCURSES_KEYCODE_F3=KEY_F(3)/*267*/, NCURSES_KEYCODE_F5=KEY_F(5)/*269*/, NCURSES_KEYCODE_F7=KEY_F(7)/*271*/ };
enum { NCURSES_KEYCODE_F2=KEY_F(2)/*266*/, NCURSES_KEYCODE_F4=KEY_F(4)/*268*/, NCURSES_KEYCODE_F6=KEY_F(6)/*270*/, NCURSES_KEYCODE_F8=KEY_F(8)/*72*/ };
enum { NCURSES_KEYCODE_UNDEFINED=ERR, NCURSES_KEYCODE_SHIFT = KEY_DUMMY/*NCURSES_KEYCODE_UNDEFINED*/, NCURSES_KEYCODE_CTRL = KEY_DUMMY /*NCURSES_KEYCODE_UNDEFINED*/ };


static const int NcursesKeyCodeToC64key [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = {
//      0    1     2    3    4    5   6    7 (DC00/DC01)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
   { KEY_DC, '\r'/*KEY_ENTER*/, KEY_RIGHT, NCURSES_KEYCODE_F7, NCURSES_KEYCODE_F1, NCURSES_KEYCODE_F3, NCURSES_KEYCODE_F5, KEY_DOWN },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
     { '3', 'w', 'a', '4', 'z', 's', 'e',  NCURSES_KEYCODE_SHIFT },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
     { '5', 'r', 'd', '6', 'c', 'f', 't', 'x' },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
     { '7', 'y', 'g', '8', 'b', 'h', 'u', 'v' },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
     { '9', 'i', 'j', '0', 'm', 'k', 'o', 'n' },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
     { '=', 'p', 'l', '-', '.', ';', /*KEY_DUMMY*/'['/*KEY_DUMMY*/, ',' },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { KEY_IC, ']'/*'*'*/, '\''/*NCURSES_KEY_DUMMY*/, KEY_HOME, NCURSES_KEYCODE_SHIFT, '\\'/*KEY_DUMMY*//*'='*/, KEY_NPAGE /*KEY_NEXT*/ , '/' },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
     { '1', '`', '\t', '2', ' ', NCURSES_KEYCODE_CTRL, 'q', NCURSES_KEYCODE_ESC /*KEY_BREAK*/ } // //SDLK_ESCAPE
};

enum { KEY_KP_ENTER=KEY_DUMMY, KEY_KP0=KEY_DUMMY, KEY_KP1=KEY_DUMMY, KEY_KP2=KEY_DUMMY, KEY_KP3=KEY_DUMMY, KEY_KP4=KEY_DUMMY,
       KEY_KP5=KEY_DUMMY, KEY_KP6=KEY_DUMMY, KEY_KP7=KEY_DUMMY, KEY_KP8=KEY_DUMMY, KEY_KP9=KEY_DUMMY,
       KEY_KP_PLUS=KEY_DUMMY, KEY_KP_MINUS=KEY_DUMMY,  KEY_KP_DIVIDE=KEY_DUMMY, KEY_KP_MULTIPLY=KEY_DUMMY,
     };
static const int NcursesKeyCodeToC64key_Alternative [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = { //extra PC-keyboard keys to expand C64 key-capabilities
//      0    1     2    3    4    5   6    7 (DC00/DC01)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
    { KEY_BACKSPACE /*KEY_BACKSPACE_ALTERNATIVE*/, KEY_KP_ENTER, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
    { KEY_KP3, KEY_DUMMY, KEY_DUMMY, KEY_KP4, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
    { KEY_KP5, KEY_DUMMY, KEY_DUMMY, KEY_KP6, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
    { KEY_KP7, KEY_DUMMY, KEY_DUMMY, KEY_KP8, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
    { KEY_KP9, KEY_DUMMY, KEY_DUMMY, KEY_KP0, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
    { KEY_KP_PLUS, KEY_DUMMY, KEY_DUMMY, KEY_KP_MINUS, KEY_DUMMY, KEY_DUMMY/*'['*//*':'*/, KEY_DUMMY, KEY_DUMMY },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { KEY_DUMMY, KEY_DUMMY, /*']'*/KEY_DUMMY/*'\''*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*'\\'*/, KEY_DUMMY, KEY_NEXT/*KEY_NPAGE*/ },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
    { KEY_KP1, KEY_END, KEY_DUMMY, KEY_KP2, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY /*NCURSES_KEYCODE_ESC*/ },
};

static const int NcursesKeyCodeToC64key_Shift [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = { //for shift-modifiers (those present on C64 without Shift, and several of those not, like cursor-left/up)
//      0    1     2    3    4    5   6    7 (DC00/DC01)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
   { KEY_SDC/*KEY_IC*/, '|'/*KEY_DUMMY*//*'\n'*//*KEY_ENTER*/, KEY_LEFT, NCURSES_KEYCODE_F8, NCURSES_KEYCODE_F2, NCURSES_KEYCODE_F4, NCURSES_KEYCODE_F6, KEY_UP },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
     { '#', 'W', 'A', '$', 'Z', 'S', 'E',  NCURSES_KEYCODE_SHIFT },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
     { '%', 'R', 'D', '^', 'C', 'F', 'T', 'X' },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
     { '&', 'Y', 'G', '*', 'B', 'H', 'U', 'V' },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
     { '(', 'I', 'J', ')', 'M', 'K', 'O', 'N' },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
     { KEY_DUMMY/*modifed to octave-select: '+'*/, 'P', 'L', KEY_DUMMY/*modifed to octave-select:'_'*/, '>', '{'/*':'*/, KEY_DUMMY, '<' },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { KEY_SIC, KEY_DUMMY/*'*'*/, '}'/*'\"'*//*NCURSES_KEY_DUMMY*/, /*KEY_DUMMY*/KEY_SHOME, NCURSES_KEYCODE_SHIFT, KEY_DUMMY/*'='*/, KEY_PPAGE /*KEY_PREVIOUS*/, '?' },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
     { '!', '~', KEY_BTAB, '@', NCURSES_KEYCODE_CTRL_SPACE/*KEY_DUMMY*//*' '*/, NCURSES_KEYCODE_CTRL, 'Q', KEY_DUMMY /*NCURSES_KEYCODE_ESC*/ /*KEY_BREAK*/ } //NCURSES_KEYCODE_ESC //SDLK_ESCAPE
};

static const int NcursesKeyCodeToC64key_CBMkey [C64_KEYTABLE_ROWS][8] = { //for ctrl-modifiers ('C='/CBM key on C64)
//      0    1     2    3    4    5   6    7 (DC00/DC01)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
   {  '\b', KEY_DUMMY/*KEY_ENTER*/, KEY_SRIGHT, NCURSES_KEYCODE_CTRL__Fx+7, NCURSES_KEYCODE_CTRL__Fx+1, NCURSES_KEYCODE_CTRL__Fx+3, NCURSES_KEYCODE_CTRL__Fx+5, KEY_DUMMY/*KEY_SNEXT*/ },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
     { KEY_DUMMY/*clashes with ESC: NCURSES_KEYCODE_CTRL_3*/, TUI_CTRL+'w', TUI_CTRL+'a', NCURSES_KEYCODE_CTRL_4, TUI_CTRL+'z', TUI_CTRL+'s', TUI_CTRL+'e',  NCURSES_KEYCODE_SHIFT },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
     { NCURSES_KEYCODE_CTRL_5, TUI_CTRL+'r', TUI_CTRL+'d', NCURSES_KEYCODE_CTRL_6, TUI_CTRL+'c', TUI_CTRL+'f', TUI_CTRL+'t', TUI_CTRL+'x' },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
     { NCURSES_KEYCODE_CTRL_7, TUI_CTRL+'y', TUI_CTRL+'g', KEY_DUMMY/*clashes: NCURSES_KEYCODE_CTRL_8*/, TUI_CTRL+'b', TUI_CTRL+'h', TUI_CTRL+'u', TUI_CTRL+'v' },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
     { KEY_DUMMY, KEY_DUMMY/*clashes with TAB: TUI_CTRL+'i'*/, TUI_CTRL+'j', KEY_DUMMY, KEY_DUMMY/*clash with ENTER: TUI_CTRL+'m'*/, TUI_CTRL+'k', TUI_CTRL+'o', TUI_CTRL+'n' },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
     { '+'/*KEY_DUMMY*/, TUI_CTRL+'p', TUI_CTRL+'l', '_'/*KEY_DUMMY*//*clashes: NCURSES_KEYCODE_CTRL_7*/, NCURSES_KEYCODE_SHIFT__Fx+6/*paging on old console:KEY_SPREVIOUS*//*KEY_DUMMY*/, KEY_DUMMY, KEY_DUMMY, NCURSES_KEYCODE_SHIFT__Fx+5/*paging on old console:KEY_SNEXT*//*KEY_DUMMY*/ },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { KEY_DUMMY, KEY_DUMMY, NCURSES_KEY_DUMMY, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_HOME*/, NCURSES_KEYCODE_SHIFT, KEY_DUMMY, KEY_DUMMY/*KEY_NPAGE*/, KEY_DUMMY/*clashes: NCURSES_KEYCODE_CTRL_SLASH*/ },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
     { KEY_DUMMY/*no Ctrl version'*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*clashes with ctrl+Space: NCURSES_KEYCODE_CTRL_2*/, KEY_DUMMY/*used as shift+space: NCURSES_KEYCODE_CTRL_SPACE*/, NCURSES_KEYCODE_CTRL, TUI_CTRL+'q', KEY_DUMMY /*NCURSES_KEYCODE_ESC*/ /*KEY_BREAK*/ } //NCURSES_KEYCODE_ESC //SDLK_ESCAPE
};
static const int NcursesKeyCodeToC64key_CBMkey_Alternative [C64_KEYTABLE_ROWS][8] = { //for ctrl-modifiers ('C='/CBM key on C64),
//      0    1     2    3    4    5   6    7 (DC00/DC01)   //like substituting unsupported Ctrl+F1 by Shift+F1 on dumber terminals (like linux/fbcon)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
   {  KEY_DUMMY/*'\b'*/, KEY_DUMMY/*KEY_ENTER*/, KEY_DUMMY/*KEY_SRIGHT*/, KEY_DUMMY/*used as reset now: NCURSES_KEYCODE_SHIFT__Fx+7*/, NCURSES_KEYCODE_SHIFT__Fx+1, NCURSES_KEYCODE_SHIFT__Fx+3, KEY_DUMMY/*used as C=+, subtune-change now: NCURSES_KEYCODE_SHIFT__Fx+5*/, KEY_DUMMY/*KEY_SNEXT*/ },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
     { KEY_DUMMY/*clashes with ESC: NCURSES_KEYCODE_CTRL_3*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_4*/, TUI_CTRL+'u'/*KEY_DUMMY*/, KEY_DUMMY, KEY_DUMMY,  NCURSES_KEYCODE_SHIFT },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
     { KEY_DUMMY/*NCURSES_KEYCODE_CTRL_5*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_6*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
     { KEY_DUMMY/*NCURSES_KEYCODE_CTRL_7*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*clashes: NCURSES_KEYCODE_CTRL_8*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
     { KEY_DUMMY, KEY_DUMMY/*clashes with TAB: TUI_CTRL+'i'*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*clash with ENTER: TUI_CTRL+'m'*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
     { KEY_DUMMY/*'+'*//*KEY_DUMMY*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*'_'*//*KEY_DUMMY*//*clashes: NCURSES_KEYCODE_CTRL_MINUS*/, NCURSES_KEYCODE_CTRL_END/*KEY_SEND*//*KEY_DUMMY*/, KEY_DUMMY, KEY_DUMMY, NCURSES_KEYCODE_CTRL_HOME/*KEY_SHOME*//*KEY_DUMMY*/ },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { KEY_DUMMY, KEY_DUMMY, NCURSES_KEY_DUMMY, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_HOME*/, NCURSES_KEYCODE_SHIFT, KEY_DUMMY, KEY_DUMMY /*KEY_NPAGE*/, KEY_DUMMY/*clashes: NCURSES_KEYCODE_CTRL_SLASH*/ },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
     { KEY_DUMMY/*no Ctrl version'*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*clashes with ctrl+Space: NCURSES_KEYCODE_CTRL_2*/, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_SPACE*/, NCURSES_KEYCODE_CTRL, KEY_DUMMY, KEY_DUMMY /*NCURSES_KEYCODE_ESC*/ /*KEY_BREAK*/ } //NCURSES_KEYCODE_ESC //SDLK_ESCAPE
};

static const int NcursesKeyCodeToC64key_Shift_plus_CBMkey [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = { //for shift+ctrl-modifiers ('Shift+C='/CBM key on C64)
//      0    1     2    3    4    5   6    7 (DC00/DC01)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
   {  KEY_DUMMY/*'\b'*/, KEY_DUMMY/*KEY_ENTER*/, KEY_SLEFT, NCURSES_KEYCODE_CTRL__Fx+8, NCURSES_KEYCODE_CTRL__Fx+2, NCURSES_KEYCODE_CTRL__Fx+4, NCURSES_KEYCODE_CTRL__Fx+6, KEY_DUMMY/*KEY_SPREVIOUS*/ },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
     { KEY_DUMMY/*clashes with ESC: NCURSES_KEYCODE_CTRL_3*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_4*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY,  NCURSES_KEYCODE_SHIFT },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
     { KEY_DUMMY/*NCURSES_KEYCODE_CTRL_5*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY /*NCURSES_KEYCODE_CTRL_6*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
     { KEY_DUMMY/*NCURSES_KEYCODE_CTRL_7*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*clashes: NCURSES_KEYCODE_CTRL_8*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
     { KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
     { KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_MINUS*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { KEY_DUMMY, KEY_DUMMY, NCURSES_KEY_DUMMY, NCURSES_KEYCODE_CTRL_HOME, NCURSES_KEYCODE_SHIFT, KEY_DUMMY, KEY_DUMMY /*KEY_NPAGE*/, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_SLASH*/ },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
     { KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*clashes with ctrl+Space: NCURSES_KEYCODE_CTRL_2*/, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_SPACE*/, NCURSES_KEYCODE_CTRL, KEY_DUMMY, KEY_DUMMY /*NCURSES_KEYCODE_ESC*/ /*KEY_BREAK*/ } //NCURSES_KEYCODE_ESC //SDLK_ESCAPE
};
static const int NcursesKeyCodeToC64key_Shift_plus_CBMkey_Alternative [C64_KEYTABLE_ROWS][C64_KEYTABLE_COLUMNS] = { //for shift+ctrl-modifiers ('Shift+C='/CBM key on C64)
//      0    1     2    3    4    5   6    7 (DC00/DC01) //like substituting unsupported Ctrl+F2 (Ctrl+Shift+F1) by Shift+F2 on dumber terminals (like linux/fbcon)
// 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
   {  KEY_DUMMY/*'\b'*/, KEY_DUMMY/*KEY_ENTER*/, KEY_DUMMY/*KEY_SLEFT*/, KEY_DUMMY/*Used as exit: NCURSES_KEYCODE_SHIFT__Fx+8*/, NCURSES_KEYCODE_SHIFT__Fx+2, NCURSES_KEYCODE_SHIFT__Fx+4, KEY_DUMMY/*Used as reset: NCURSES_KEYCODE_SHIFT__Fx+6*/, KEY_DUMMY/*KEY_SPREVIOUS*/ },
// 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
     { KEY_DUMMY/*clashes with ESC: NCURSES_KEYCODE_CTRL_3*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_4*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY,  NCURSES_KEYCODE_SHIFT },
// 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
     { KEY_DUMMY/*NCURSES_KEYCODE_CTRL_5*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY /*NCURSES_KEYCODE_CTRL_6*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
     { KEY_DUMMY/*NCURSES_KEYCODE_CTRL_7*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*clashes: NCURSES_KEYCODE_CTRL_8*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
     { KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
     { KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_MINUS*/, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY },
// 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
    { KEY_DUMMY, KEY_DUMMY, NCURSES_KEY_DUMMY, NCURSES_KEYCODE_CTRL_HOME, NCURSES_KEYCODE_SHIFT, KEY_DUMMY, KEY_DUMMY /*KEY_NPAGE*/, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_SLASH*/ },
// 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)
     { KEY_DUMMY, KEY_DUMMY, KEY_DUMMY, KEY_DUMMY/*clashes with ctrl+Space: NCURSES_KEYCODE_CTRL_2*/, KEY_DUMMY/*NCURSES_KEYCODE_CTRL_SPACE*/, NCURSES_KEYCODE_CTRL, KEY_DUMMY, KEY_DUMMY /*NCURSES_KEYCODE_ESC*/ /*KEY_BREAK*/ } //NCURSES_KEYCODE_ESC //SDLK_ESCAPE
};

                                                                        //                  $3B, a..z:$61..$7A, $2D,$5C, $27,$2C,$2E,$2F,$3D,$5B,$5D, 0..9:$30..$39
static const int DvorakKeyToC64key [] = { //dvorak to C64 US piano-keys  //Dvorak piano-keys: ;qjkxbmwvz   aoeuidhtns-\  ',.pyfgcrl/=  1234567890[]
//    $20, $21, $22, $23, $24, $25, $26,                                 //C64 US piano-keys  zxcvbnm,./   asdfghjkl;'\  qwertyuiop[]  1234567890-=
//    ' '   !    "    #    $    %    &
       0,   0,   0,   0,   0,   0,   0,

//    $27, $28, $29, $2A, $2B, $2C, $2D, $2E, $2F, $30, $31, $32, $33, $34, $35, $36, $37, $38, $39, $3A, $3B, $3C, $3D, $3E, $3F, $40
//     '    (    )    *    +    ,    -    .    /    0    1    2    3    4    5    6    7    8    9    :    ;    <    =    >    ?    @
//US:  q                        w    '    e    [                                                           z         ]
      0x3E, 0,   0,   0,   0, 0x09,  0, 0x0E,0x2E,  0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 0x0C,  0, 0x31,  0,   0,   0,

//    $41, $42, $43, $44, $45, $46, $47, $48, $49, $4A, $4B, $4C, $4D, $4E, $4F, $50, $51, $52, $53, $54, $55, $56, $57, $58, $59, $5A, $5B, $5C, $5D, $5E, $5F, $60
//     A    B    C    D    E    F    G    H    I    J    K    L    M    N    O    P    Q    R    S    T    U    V    W    X    Y    Z
       0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,

//    $61, $62, $63, $64, $65, $66, $67, $68, $69, $6A, $6B, $6C, $6D, $6E, $6F, $70, $71, $72, $73, $74, $75, $76, $77, $78, $79, $7A,  [    \    ]    ^    _    `
//     a,   b,   c,   d,   e,   f,   g,   h,   i,   j,   k,   l,   m,   n,   o,   p,   q,   r,   s,   t,   u,   v,   w,   x,   y,   z    {    |    }    ~
//C64:0x0A,0x1C,0x14,0x12,0x0E,0x15,0x1A,0x1D,0x21,0x22,0x25,0x2A,0x24,0x27,0x26,0x29,0x3E,0x11,0x0D,0x16,0x1E,0x1F,0x09,0x17,0x19,0x0C
//US:  a    n    i    h    d    y    u    j    g    c    v    p    m    l    s    r    x    o   ;->:  k    f    .    ,    b    t    /
     0x0A,0x27,0x21,0x1D,0x12,0x19,0x1E,0x22,0x1A,0x14,0x1F,0x29,0x24,0x2A,0x0D,0x11,0x17,0x26,0x2D,0x25,0x15,0x2C,0x2F,0x1C,0x16,  0
};

#endif //ENABLED_TUI_KEYS


#if (ENABLED_SDL_EVENTS) //(ENABLED_SDL)

static byte EmptyKeyArray[] = { //It's written by argument-file loader as a simulation of keypresses
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
};

#endif

