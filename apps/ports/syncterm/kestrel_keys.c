/* The keyboard for SyncTERM: the cart's input exports (docs/sealed-loader.js and the board's glass call them)
 * become ciolib key codes in a ring, read by kestrel_cio.c's kbhit/getch. A ciolib code is a byte, or for an
 * extended key 0x00 then its scan code (CIO_KEY_UP = 0x4800 is 0x00, 0x48), as retro.c's keybuf.
 *
 *   key(cp)       printable codepoint, 8 Backspace, 13 Enter, 0xE001.. F1-F10, Ins, Del, Esc, Alt (a toggle),
 *                 0xE014.. Ctrl / Shift (held: keyUp releases), 0xE019.. Tab, Home, End, PgUp, PgDn
 *   keyUp(code)   the same codes, on release
 *   input(dir)    arrows (0 up, 1 down, 2 left, 3 right)
 * No SDL here: SyncTERM's own SDL path is not built (kestrel_cio.c says why). */
#include <stdint.h>
#include "kestrel_keys.h"

#define KQ 256
static uint8_t ring[KQ];
static unsigned head, tail;
static int ctrl, alt;

static void put(uint8_t b)
{
    unsigned next = (tail + 1) % KQ;
    if (next != head) { ring[tail] = b; tail = next; }
}
static void put_code(uint16_t c)
{
    if ((tail + 2) % KQ == head || (tail + 1) % KQ == head) return;   /* full: drop the whole key */
    put((uint8_t)(c & 0xff));
    if (c > 0xff || c == 0) put((uint8_t)(c >> 8));
}

int kestrel_keys_waiting(void) { return head != tail; }
int kestrel_keys_get(void)
{
    if (head == tail) return -1;
    int b = ring[head];
    head = (head + 1) % KQ;
    return b;
}
void kestrel_keys_push(uint16_t code) { put_code(code); }

/* Alt + a letter: the PC scan code in the high byte (ciolib's CIO_KEY_ALT range, as retro.c's table). */
static const uint8_t alt_scan[26] = { 0x1e, 0x30, 0x2e, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32,
                                      0x31, 0x18, 0x19, 0x10, 0x13, 0x1f, 0x14, 0x16, 0x2f, 0x11, 0x2d, 0x15, 0x2c };

static uint16_t special(uint32_t cp)
{
    if (cp >= 0xE001 && cp <= 0xE00A) return (uint16_t)((0x3b + (cp - 0xE001)) << 8);   /* F1..F10 */
    switch (cp) {
    case 8: return 0x08;
    case 13: return 0x0d;
    case 0xE00B: return 0x5200;   /* Insert */
    case 0xE00C: return 0x5300;   /* Delete */
    case 0xE012: return 0x1b;     /* Esc */
    case 0xE019: return 0x09;     /* Tab */
    case 0xE01A: return 0x4700;   /* Home */
    case 0xE01B: return 0x4f00;   /* End */
    case 0xE01C: return 0x4900;   /* PgUp */
    case 0xE01D: return 0x5100;   /* PgDn */
    default: return 0xffff;
    }
}

__attribute__((export_name("ownsKeyboard"))) int ownsKeyboard(void) { return 1; }
__attribute__((export_name("drawsOwnPointer"))) int drawsOwnPointer(void) { return 1; }

__attribute__((export_name("key"))) void key(uint32_t cp)
{
    if (cp == 0xE014 || cp == 0xE016) { ctrl = 1; return; }
    if (cp == 0xE013 || cp == 0xE018) { alt = !alt; return; }
    if (cp == 0xE015 || cp == 0xE017) return;          /* Shift: the codepoint is already shifted */
    uint16_t s = special(cp);
    if (s != 0xffff) { put_code(s); return; }
    if (cp < 32 || cp > 126) return;
    uint8_t c = (uint8_t)cp;
    uint8_t lower = (c >= 'A' && c <= 'Z') ? (uint8_t)(c + 32) : c;
    if (alt && lower >= 'a' && lower <= 'z') { put_code((uint16_t)(alt_scan[lower - 'a'] << 8)); alt = 0; return; }
    if (ctrl && lower >= 'a' && lower <= 'z') { put_code((uint16_t)(lower & 0x1f)); return; }
    put_code(c);
}

__attribute__((export_name("keyUp"))) void keyUp(uint32_t code)
{
    if (code == 0xE014 || code == 0xE016) ctrl = 0;
}

static const uint16_t arrows[4] = { 0x4800, 0x5000, 0x4b00, 0x4d00 };
__attribute__((export_name("input"))) void input(uint32_t dir) { if (dir < 4) put_code(arrows[dir]); }
__attribute__((export_name("inputRelease"))) void inputRelease(uint32_t dir) { (void)dir; }
__attribute__((export_name("pointer"))) void pointer(int x, int y, uint32_t b) { (void)x; (void)y; (void)b; }
