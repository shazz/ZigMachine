/* SDL_GetKeyName on the cart (opt-in, src/opt): printable keys are their upper-case character, the rest
 * SDL 2's names for the keys the cart's input ABI can produce (kestrel_input.c) plus the usual editing keys. */
#include <SDL2/SDL.h>

static const struct { SDL_Keycode k; const char *n; } names[] = {
    { SDLK_RETURN, "Return" }, { SDLK_ESCAPE, "Escape" }, { SDLK_BACKSPACE, "Backspace" }, { SDLK_TAB, "Tab" },
    { SDLK_SPACE, "Space" }, { SDLK_DELETE, "Delete" }, { SDLK_INSERT, "Insert" }, { SDLK_HOME, "Home" },
    { SDLK_END, "End" }, { SDLK_PAGEUP, "PageUp" }, { SDLK_PAGEDOWN, "PageDown" }, { SDLK_UP, "Up" },
    { SDLK_DOWN, "Down" }, { SDLK_LEFT, "Left" }, { SDLK_RIGHT, "Right" }, { SDLK_F1, "F1" }, { SDLK_F2, "F2" },
    { SDLK_F3, "F3" }, { SDLK_F4, "F4" }, { SDLK_F5, "F5" }, { SDLK_F6, "F6" }, { SDLK_F7, "F7" }, { SDLK_F8, "F8" },
    { SDLK_F9, "F9" }, { SDLK_F10, "F10" }, { SDLK_F11, "F11" }, { SDLK_F12, "F12" }, { SDLK_LSHIFT, "Left Shift" },
    { SDLK_RSHIFT, "Right Shift" }, { SDLK_LCTRL, "Left Ctrl" }, { SDLK_RCTRL, "Right Ctrl" }, { SDLK_LALT, "Left Alt" },
    { SDLK_RALT, "Right Alt" }, { SDLK_KP_PLUS, "Keypad +" }, { SDLK_KP_MINUS, "Keypad -" },
    { SDLK_KP_MULTIPLY, "Keypad *" }, { SDLK_KP_DIVIDE, "Keypad /" }, { SDLK_KP_ENTER, "Keypad Enter" },
};

const char *SDL_GetKeyName(SDL_Keycode key)
{
    static char one[2];
    for (unsigned i = 0; i < sizeof names / sizeof names[0]; i++) if (names[i].k == key) return names[i].n;
    if (key > ' ' && key < 127) { one[0] = (char)toupper(key); one[1] = 0; return one; }
    return "";
}
