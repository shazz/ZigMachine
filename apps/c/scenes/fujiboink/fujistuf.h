// ---------------------------------------------------------------------------
// fujistuf.h: FUJISTUF.S (Xanth Park, 1986) on the sealed ZigMachine.
//
// The original's assembly half: moov/kleer, the 3-plane block mover and
// clearer, and the interrupts that make the rainbow. Included by exactly one
// file, scenes/fujiboink.c (the port of FUJIBOIN.C), the way FUJI.BAT linked
// fujistuf.o into fujiboin.prg.
//
// THE SCREEN. An ST low-res screen is four interleaved bitplanes; a ZigMachine
// plane is one palette index per pixel. Each pixel here holds the 4-bit value
// the four ST planes spell (0..15) and the plane's palette entries 0..15 ARE the
// sixteen ST colour registers, so the picture means exactly what it meant on
// the ST. moov and kleer keep their ST semantics: they take ST byte offsets and
// touch planes 1..3 only, leaving plane 0 (the checkerboard) alone. That is the
// whole trick of the transparent shadow (Behind the Bit Planes, Figure 3).
//
// THE RASTERS are real: the colour registers are rewritten per scanline from
// the plane's HBL, never painted as pixels. The fuji's face pixels hold index 4
// or 5 everywhere; only the register changes from line to line.
// ---------------------------------------------------------------------------
#ifndef FUJISTUF_H
#define FUJISTUF_H

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

// --- the sealed ABI (offsets mirror machine/sdk/memmap.zig) -----------------
__attribute__((import_module("env"), import_name("hwVideoBase")))
extern int hwVideoBase(void);

#define OFF_PAL        0x0100 // plane 0 palette: 256 x RGBA
#define OFF_VRAM       0x1100 // the framebuffer pool; plane p's default base is +p*64000
#define FB_BYTES       64000  // one 320x200 plane
#define REG_BACKGROUND 0x04   // u32: the border, which an ST paints in colour 0
#define REG_FB_HBL_ID  0x20   // u16 per plane
#define REG_FB_HBL_POS 0x28   // u16 per plane
#define REG_FB_BASE    0x44   // u32 per plane: the screen base (Setscreen's physbase)

#define ST_W 320
#define ST_H 200
#define ST_LINE 160 // bytes per ST low-res line

static int video_base;
static inline u8 *io(unsigned off) { return (u8 *)(video_base + off); }

// The two screens: plane 0's framebuffer and plane 1's. Plane 1 is never shown
// as a plane; its buffer is simply the second screen, as screenbuff[] was.
static u8 *screen[2];
static u32 screen_fb[2]; // their FB_BASE values
static u32 physbase;     // what Setscreen asked for; the VBL latches it

// --- the colour registers $FF8240..$FF825E --------------------------------
static u16 st_color[16];

// A register write: palette entry n, and the border when it is colour 0. An ST
// colour is 3 bits a gun; the machine's grid is nibble*32 (docs/HARDWARE_SPEC.md).
static void setcolor(int n, u16 c) {
    st_color[n] = c;
    const u32 rgba = 0xFF000000u | ((c & 7u) * 32u) << 16 | (((c >> 4) & 7u) * 32u) << 8 | ((c >> 8) & 7u) * 32u;
    ((u32 *)io(OFF_PAL))[n] = rgba;
    if (n == 0) *(u32 *)io(REG_BACKGROUND) = rgba;
}

// --- moov / kleer --------------------------------------------------------
// One 16-pixel group at ST byte offset `off` of screen `scr`. The ST writes it
// wherever the offset points, so a group one word left of column 0 lands at the
// end of the line above, exactly as movit()'s --newleft does on the ST. An
// offset off the 32000-byte screen is not written (unreachable from FUJIBOIN.C).
static u8 *group_at(u8 *scr, int off) {
    if (off < 0 || off >= ST_LINE * ST_H) return 0;
    return scr + (off / ST_LINE) * ST_W + (off % ST_LINE) / 8 * 16;
}

static inline u16 be16(const u8 *p) { return (u16)(p[0] << 8 | p[1]); }

// void moov(src,dst,srcinc,dstinc,i,j): i+1 lines of j+1 groups, planes 1..3
// from src (three words a group), plane 0 of dst untouched. The increments are
// in words, as in the original (asl #1).
static void moov(const u8 *src, u8 *scr, int dst, int srcinc, int dstinc, int i, int j) {
    for (u32 l = 0; l <= (u16)i; l++) { // dbra: i+1 times
        for (u32 g = 0; g <= (u16)j; g++) {
            u8 *d = group_at(scr, dst);
            const u16 p1 = be16(src), p2 = be16(src + 2), p3 = be16(src + 4);
            for (int b = 0; d && b < 16; b++) {
                const int s = 15 - b;
                const u8 v = (u8)(((p1 >> s) & 1) << 1 | ((p2 >> s) & 1) << 2 | ((p3 >> s) & 1) << 3);
                d[b] = (u8)((d[b] & 1) | v);
            }
            src += 6;
            dst += 8;
        }
        src += srcinc * 2;
        dst += dstinc * 2;
    }
}

// void kleer(dst,dstinc,i,j): the same walk, clearing planes 1..3.
static void kleer(u8 *scr, int dst, int dstinc, int i, int j) {
    for (u32 l = 0; l <= (u16)i; l++) {
        for (u32 g = 0; g <= (u16)j; g++) {
            u8 *d = group_at(scr, dst);
            for (int b = 0; d && b < 16; b++) d[b] &= 1;
            dst += 8;
        }
        dst += dstinc * 2;
    }
}

// --- the interrupts: _inton/_intoff, vblank, hb0/hblank/hback --------------
static int ints_on;       // between inton() and intoff()
static int fujiy, fflag;  // _fujiy, _fflag: C sets them, the VBL reads them
static const u16 *kolptr; // _kolptr: kolors[view], 72 lines x (rainbow, side)
static u16 kolbak;        // _kolbak: the face colour of a fuji seen from the back

static int hb_start;     // first line the Timer B routine colours (the hb0 count)
static int hb_front;     // hblank (front: rainbow + side) or hback (side only)
static const u16 *ix;    // ix: the colour pointer the routine walks
static int k72;          // k72: lines left (a byte)
static int hb_tail;      // the one more line Timer B still counts after clr.b dataB

// vblank: arm Timer B for the frame and set the back colour. Also the
// physbase latch, which the ST's own VBL does for Setscreen.
static void vblank(void) {
    *(u32 *)io(REG_FB_BASE) = physbase;
    if (!ints_on) return;
    k72 = 72;
    hb_tail = 0;
    hb_front = fflag != 0;
    setcolor(4, kolbak);
    setcolor(5, kolbak);
    // hb0 counts yknt = fujiy-1 (a byte) line ends down to 0, then the first
    // hblank at the end of line fujiy-1 colours line fujiy. yknt = 0 wraps to
    // 255, and 256 line ends never come in a 200-line frame.
    const u8 yknt = (u8)(fujiy - 1);
    hb_start = yknt == 0 ? 257 : yknt + 1;
    ix = kolptr;
}

// Timer B, event count 1: one interrupt at the end of each displayed line. The
// machine calls the plane's HBL BEFORE drawing logical line `line`, which is the
// same instant for the picture: after line-1, before line. Budget: hblank is
// four move.w to colour registers, hback two, the ST's own figure.
//
// 73 lines, not 72. After the 72nd, `clr.b dataB` only writes the timer's
// RELOAD value: the running counter still holds 1, so one more interrupt comes
// at the end of the next line, reading the pair after kolors[view] (and then the
// counter reloads with 0 = 256 lines, which never come). The pair after view v is
// view v+1's first, which is why FUJIBOIN.C writes the title colour into
// kolors[26][1] ("!!!"): that 73rd line sets colour 7 for the commercial below.
// Hatari's captures of the original show it.
static void timer_b(u32 line) {
    if (!ints_on || !ix || (k72 == 0 && !hb_tail) || (int)line < hb_start) return;
    if (hb_front) {
        setcolor(4, ix[0]); // move.w (a0),color4
        setcolor(5, ix[0]); // move.w (a0)+,color5
    }
    setcolor(6, ix[1]);     // move.w (a0),color6
    setcolor(7, ix[1]);     // move.w (a0)+,color7
    ix += 2;
    if (hb_tail) { hb_tail = 0; return; } // the extra line: the counter now reloads with 256
    k72--;                  // dec.b k72
    if (k72 == 0) hb_tail = 1; // after 72 lines: clr.b dataB
}

#endif
