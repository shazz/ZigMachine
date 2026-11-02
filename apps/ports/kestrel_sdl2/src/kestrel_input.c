/* Input for pt2-clone: the cart's input exports (as docs/sealed-loader.js and the board glass call them)
 * become an SDL event queue, mouse state and modifier state.
 *
 *   key(cp)        printable codepoint, 8 Backspace, 13 Enter, 0xE001.. F1-F10/Ins/Del/Esc/Alt, 0xE014.. Ctrl/Shift
 *   keyUp(code)    the same codes, on release
 *   input(dir)     arrows (0 up, 1 down, 2 left, 3 right); inputRelease(dir) on release
 *   pointer(x,y,b) visible-area coordinates (x doubled for low res, origin at the 320x200 window), b bit0 = left
 * kestrel_input_origin(dx, dy) says where the program's (0,0) is relative to that window.
 */
#include <SDL2/SDL.h>

#define QLEN 64
static SDL_Event queue[QLEN];
static unsigned qhead, qtail;
static int mouse_x, mouse_y;
static Uint32 mouse_buttons;
static Uint16 mods;
static int text_input;
static int org_x, org_y;       /* program coords = (visible x / 2 + org_x, visible y + org_y) */
void kestrel_input_origin(int dx, int dy) { org_x = dx; org_y = dy; }

static void push(const SDL_Event *e)
{
    unsigned next = (qtail + 1) % QLEN;
    if (next == qhead) return;          /* full: drop (pt2 polls every frame, so it never fills) */
    queue[qtail] = *e;
    qtail = next;
}

int SDL_PollEvent(SDL_Event *e)
{
    if (qhead == qtail) return 0;
    if (e) *e = queue[qhead];
    qhead = (qhead + 1) % QLEN;
    return 1;
}
int SDL_PushEvent(SDL_Event *e) { push(e); return 1; }
/* PEEK / GET of up to n queued events of any type (the type range is not filtered: nothing needs it). */
int SDL_PeepEvents(SDL_Event *e, int n, SDL_eventaction a, Uint32 minType, Uint32 maxType)
{
    (void)minType; (void)maxType;
    if (a == SDL_ADDEVENT) { for (int i = 0; i < n; i++) push(&e[i]); return n; }
    int got = 0;
    for (unsigned q = qhead; q != qtail && got < n; q = (q + 1) % QLEN) if (e) e[got++] = queue[q]; else got++;
    if (a == SDL_GETEVENT) qhead = (qhead + (unsigned)got) % QLEN;
    return got;
}
Uint32 SDL_GetMouseState(int *x, int *y) { if (x) *x = mouse_x; if (y) *y = mouse_y; return mouse_buttons; }
Uint32 SDL_GetGlobalMouseState(int *x, int *y) { return SDL_GetMouseState(x, y); }
SDL_Keymod SDL_GetModState(void) { return (SDL_Keymod)mods; }
void SDL_SetModState(SDL_Keymod m) { mods = (Uint16)m; }
void SDL_StartTextInput(void) { text_input = 1; }
void SDL_StopTextInput(void) { text_input = 0; }

/* A codepoint or KEY_CODES value -> scancode + keycode; 0 scancode = not a key pt2 knows. */
static void map_key(Uint32 cp, SDL_Scancode *sc, SDL_Keycode *sym)
{
    *sym = 0; *sc = SDL_SCANCODE_UNKNOWN;
    if (cp >= 'A' && cp <= 'Z') cp += 'a' - 'A';
    if (cp >= 'a' && cp <= 'z') { *sc = (SDL_Scancode)(SDL_SCANCODE_A + (cp - 'a')); *sym = (SDL_Keycode)cp; return; }
    if (cp >= '1' && cp <= '9') { *sc = (SDL_Scancode)(SDL_SCANCODE_1 + (cp - '1')); *sym = (SDL_Keycode)cp; return; }
    *sym = (SDL_Keycode)cp;
    switch (cp) {
    case '0': *sc = SDL_SCANCODE_0; return;
    case ' ': *sc = SDL_SCANCODE_SPACE; return;
    case 8: *sc = SDL_SCANCODE_BACKSPACE; return;
    case 13: *sc = SDL_SCANCODE_RETURN; *sym = SDLK_RETURN; return;
    case '-': case '_': *sc = SDL_SCANCODE_MINUS; *sym = '-'; return;
    case '=': case '+': *sc = SDL_SCANCODE_EQUALS; *sym = '='; return;
    case '\\': case '|': *sc = SDL_SCANCODE_BACKSLASH; *sym = '\\'; return;
    case '\'': case '"': *sc = SDL_SCANCODE_APOSTROPHE; *sym = '\''; return;
    case '/': case '?': *sc = SDL_SCANCODE_SLASH; *sym = '/'; return;
    case '<': case '>': *sc = SDL_SCANCODE_NONUSBACKSLASH; return;
    case '*': *sc = SDL_SCANCODE_KP_MULTIPLY; return;
    case 0xE012: *sc = SDL_SCANCODE_ESCAPE; *sym = SDLK_ESCAPE; return;
    case 0xE00B: *sc = SDL_SCANCODE_INSERT; *sym = SDLK_INSERT; return;
    case 0xE00C: *sc = SDL_SCANCODE_DELETE; *sym = 0x7F; return;
    case 0xE013: *sc = SDL_SCANCODE_LALT; *sym = SDLK_LALT; return;
    case 0xE014: *sc = SDL_SCANCODE_LCTRL; *sym = SDLK_LCTRL; return;
    case 0xE015: *sc = SDL_SCANCODE_LSHIFT; *sym = SDLK_LSHIFT; return;
    case 0xE016: *sc = SDL_SCANCODE_RCTRL; *sym = SDLK_RCTRL; return;
    case 0xE017: *sc = SDL_SCANCODE_RSHIFT; *sym = SDLK_RSHIFT; return;
    case 0xE018: *sc = SDL_SCANCODE_RALT; *sym = SDLK_RALT; return; /* Right Alt: pt2's play song */
    default:
        if (cp >= 0xE001 && cp <= 0xE00A) { *sc = (SDL_Scancode)(SDL_SCANCODE_F1 + (cp - 0xE001)); *sym = (SDL_Keycode)(*sc | SDLK_SCANCODE_MASK); return; }
        *sym = 0;
    }
}

static Uint16 mod_bit(SDL_Scancode sc)
{
    switch (sc) {
    case SDL_SCANCODE_LSHIFT: return KMOD_LSHIFT;
    case SDL_SCANCODE_RSHIFT: return KMOD_RSHIFT;
    case SDL_SCANCODE_LCTRL: return KMOD_LCTRL;
    case SDL_SCANCODE_RCTRL: return KMOD_RCTRL;
    case SDL_SCANCODE_LALT: return KMOD_LALT;
    case SDL_SCANCODE_RALT: return KMOD_RALT;
    default: return 0;
    }
}

static void key_event(Uint32 type, SDL_Scancode sc, SDL_Keycode sym)
{
    SDL_Event e;
    memset(&e, 0, sizeof e);
    e.type = type;
    e.key.keysym.scancode = sc;
    e.key.keysym.sym = sym;
    e.key.keysym.mod = mods;
    e.key.state = type == SDL_KEYDOWN;
    push(&e);
}

__attribute__((export_name("ownsKeyboard"))) int ownsKeyboard(void) { return 1; }
__attribute__((export_name("drawsOwnPointer"))) int drawsOwnPointer(void) { return 1; }

__attribute__((export_name("key"))) void key(Uint32 cp)
{
    SDL_Scancode sc; SDL_Keycode sym;
    map_key(cp, &sc, &sym);
    if (sc == SDL_SCANCODE_UNKNOWN) return;
    Uint16 m = mod_bit(sc);
    if (m) {
        if (sc == SDL_SCANCODE_LALT && (mods & m)) { mods &= (Uint16)~m; key_event(SDL_KEYUP, sc, 0); return; } /* Alt is a toggle */
        mods |= m;
    }
    key_event(SDL_KEYDOWN, sc, sym);
    if (text_input && cp >= 32 && cp < 127) {
        SDL_Event e;
        memset(&e, 0, sizeof e);
        e.type = SDL_TEXTINPUT;
        e.text.text[0] = (char)cp;
        push(&e);
    }
}

__attribute__((export_name("keyUp"))) void keyUp(Uint32 code)
{
    SDL_Scancode sc; SDL_Keycode sym;
    map_key(code, &sc, &sym);
    if (sc == SDL_SCANCODE_UNKNOWN || sc == SDL_SCANCODE_LALT) return;
    mods &= (Uint16)~mod_bit(sc);
    key_event(SDL_KEYUP, sc, sym);
}

static const SDL_Scancode arrows[4] = { SDL_SCANCODE_UP, SDL_SCANCODE_DOWN, SDL_SCANCODE_LEFT, SDL_SCANCODE_RIGHT };
__attribute__((export_name("input"))) void input(Uint32 dir) { if (dir < 4) key_event(SDL_KEYDOWN, arrows[dir], (SDL_Keycode)(arrows[dir] | SDLK_SCANCODE_MASK)); }
__attribute__((export_name("inputRelease"))) void inputRelease(Uint32 dir) { if (dir < 4) key_event(SDL_KEYUP, arrows[dir], (SDL_Keycode)(arrows[dir] | SDLK_SCANCODE_MASK)); }

__attribute__((export_name("pointer"))) void pointer(int x, int y, Uint32 b)
{
    int nx = x / 2 + org_x, ny = y + org_y;
    Uint32 nb = (b & 1) ? SDL_BUTTON_LMASK : 0;
    if (b & 4) nb |= SDL_BUTTON_RMASK;
    if (nx != mouse_x || ny != mouse_y) {
        SDL_Event e;
        memset(&e, 0, sizeof e);
        e.type = SDL_MOUSEMOTION; e.motion.x = nx; e.motion.y = ny;
        e.motion.xrel = nx - mouse_x; e.motion.yrel = ny - mouse_y; e.motion.state = nb;
        mouse_x = nx; mouse_y = ny;
        push(&e);
    }
    for (int btn = SDL_BUTTON_LEFT; btn <= SDL_BUTTON_RIGHT; btn += 2) {
        Uint32 mask = SDL_BUTTON(btn);
        if ((nb ^ mouse_buttons) & mask) {
            SDL_Event e;
            memset(&e, 0, sizeof e);
            e.type = (nb & mask) ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
            e.button.button = (Uint8)btn; e.button.x = nx; e.button.y = ny; e.button.clicks = 1;
            push(&e);
        }
    }
    mouse_buttons = nb;
}
