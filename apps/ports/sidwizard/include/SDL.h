/* The few SDL 1.2 names SID-Wizard's own key handling uses (upstream host/keyboard.c and keyboard.h, compiled
 * unchanged): the SDL 1.2 key symbols, with SDL 1.2's values, and SDL_GetKeyState(). There is no SDL here:
 * kestrel_sw_keys.c fills the key state array from the cart's key exports. Nothing else of SDL is used (the
 * picture is drawn by kestrel_sw_video.c, the sound fed by kestrel_audio.c). */
#ifndef KESTREL_SW_SDL12_H
#define KESTREL_SW_SDL12_H
#include <stdint.h>

typedef uint8_t Uint8;
typedef uint16_t Uint16;
typedef uint32_t Uint32;

typedef enum {
    SDLK_UNKNOWN = 0, SDLK_BACKSPACE = 8, SDLK_TAB = 9, SDLK_CLEAR = 12, SDLK_RETURN = 13, SDLK_PAUSE = 19,
    SDLK_ESCAPE = 27, SDLK_SPACE = 32, SDLK_EXCLAIM = 33, SDLK_QUOTEDBL = 34, SDLK_HASH = 35, SDLK_DOLLAR = 36,
    SDLK_AMPERSAND = 38, SDLK_QUOTE = 39, SDLK_LEFTPAREN = 40, SDLK_RIGHTPAREN = 41, SDLK_ASTERISK = 42,
    SDLK_PLUS = 43, SDLK_COMMA = 44, SDLK_MINUS = 45, SDLK_PERIOD = 46, SDLK_SLASH = 47,
    SDLK_0 = 48, SDLK_1, SDLK_2, SDLK_3, SDLK_4, SDLK_5, SDLK_6, SDLK_7, SDLK_8, SDLK_9,
    SDLK_COLON = 58, SDLK_SEMICOLON = 59, SDLK_LESS = 60, SDLK_EQUALS = 61, SDLK_GREATER = 62,
    SDLK_QUESTION = 63, SDLK_AT = 64, SDLK_LEFTBRACKET = 91, SDLK_BACKSLASH = 92, SDLK_RIGHTBRACKET = 93,
    SDLK_CARET = 94, SDLK_UNDERSCORE = 95, SDLK_BACKQUOTE = 96,
    SDLK_a = 97, SDLK_b, SDLK_c, SDLK_d, SDLK_e, SDLK_f, SDLK_g, SDLK_h, SDLK_i, SDLK_j, SDLK_k, SDLK_l, SDLK_m,
    SDLK_n, SDLK_o, SDLK_p, SDLK_q, SDLK_r, SDLK_s, SDLK_t, SDLK_u, SDLK_v, SDLK_w, SDLK_x, SDLK_y, SDLK_z,
    SDLK_DELETE = 127,
    SDLK_KP0 = 256, SDLK_KP1, SDLK_KP2, SDLK_KP3, SDLK_KP4, SDLK_KP5, SDLK_KP6, SDLK_KP7, SDLK_KP8, SDLK_KP9,
    SDLK_KP_PERIOD = 266, SDLK_KP_DIVIDE, SDLK_KP_MULTIPLY, SDLK_KP_MINUS, SDLK_KP_PLUS, SDLK_KP_ENTER, SDLK_KP_EQUALS,
    SDLK_UP = 273, SDLK_DOWN, SDLK_RIGHT, SDLK_LEFT, SDLK_INSERT, SDLK_HOME, SDLK_END, SDLK_PAGEUP, SDLK_PAGEDOWN,
    SDLK_F1 = 282, SDLK_F2, SDLK_F3, SDLK_F4, SDLK_F5, SDLK_F6, SDLK_F7, SDLK_F8, SDLK_F9, SDLK_F10, SDLK_F11,
    SDLK_F12, SDLK_F13, SDLK_F14, SDLK_F15,
    SDLK_NUMLOCK = 300, SDLK_CAPSLOCK, SDLK_SCROLLOCK, SDLK_RSHIFT, SDLK_LSHIFT, SDLK_RCTRL, SDLK_LCTRL,
    SDLK_RALT, SDLK_LALT,
    SDLK_LAST = 323
} SDLKey;

Uint8 *SDL_GetKeyState(int *numkeys);

#endif
