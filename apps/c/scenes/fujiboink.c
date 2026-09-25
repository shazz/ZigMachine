// ---------------------------------------------------------------------------
// FujiBoink!  Written by Xanth Park.  23 Apr 86 (START mod: 27 Jun 86)
// START magazine, Fall 1986.      Copyright 1986 by Antic Publishing
//
// A SOURCE port, C to C, of FUJIBOIN.C (github.com/larsbrinkhoff/FujiBoink),
// with FUJISTUF.S in fujiboink/fujistuf.h. Xanth's names and structure are
// kept; GEM, XBIOS and GEMDOS calls become the sealed machine's registers.
//
// THE DATA is FUJIBOIN.D8A, produced by running the original generators in
// Hatari (TOS 1.62, low res): FUJIDRAW (the 32 views, drawn with GEM VDI),
// FUJISHAD (the side shading), GETTITLE (the commercial, from TITLE.NEO) and
// PEND, which appends them: 6800 + 109596 + 2304 = 118700 bytes.
//
// BLOCKING CODE. The original loops and calls xbios(37) (wait for the VBL)
// wherever it likes: in intro(), in titlecolor() three levels down, in qui()
// waiting for a key. A cart gets one frame() per VBL instead, so every function
// that waits is a protothread: its locals are static, PT_YIELD is xbios(37),
// and PT_CALL runs a child until the child returns. The control flow is the
// original's, line for line.
//
// TIMING: one VBL per machine tick, 60 Hz. FujiBoink was written in Seattle for
// a 60 Hz US colour ST, and the article says it bounces "at 60 frames per
// second"; the machine ticks at a fixed 60 Hz, so a tick is the author's VBL.
// (The Hatari references are PAL, 50 Hz; they are compared VBL for VBL.)
//
// SOUND: one effect, the thud. See fujiboink_thud.sndh (thud.s).
// KEYS: as the original. Space leaves; any other key sets the commercial flag;
// a key with no ASCII (F1-F10, the arrows) freezes until the next key. Escape
// also leaves, the machine's rule for every screen.
// ---------------------------------------------------------------------------
#include "fujiboink/fujistuf.h"
#include "../zigmachine_music.h"
#include "../zigmachine_tvnoise.h" // +/- tunes in through TV snow, as a Zig cart does

// [c23-extensions] #embed is C23; build.sh compiles every cart with clang's
// default C dialect, and this is the one cart that embeds a binary.
#pragma clang diagnostic ignored "-Wc23-extensions"
static const u8 D8A[] = {
#embed "../assets/screens/fujiboink/FUJIBOIN.D8A"
};
_Static_assert(sizeof(D8A) == 6800 + 109596 + 2304, "FUJIBOIN.D8A is PEND.C's 118700 bytes");

#define THUD "fujiboink_thud.sndh"

// --- protothreads: xbios(37) inside a cart's frame() ----------------------
#define PT_BEGIN(lc) switch (lc) { case 0:
#define PT_YIELD(lc) do { lc = __LINE__; return 0; case __LINE__:; } while (0)
#define PT_CALL(lc, call) do { lc = __LINE__; case __LINE__: if (!(call)) return 0; } while (0)
#define PT_END(lc) } lc = 0; return 1

#define GRID            1
#define SHADOW          2
#define FACE            4
#define NEARSIDE        6
#define BARSIDE         8
#define FARSIDE         10
#define MAXBOT          198
#define MAXRIGHT        19

static int advertising = 0; // flag: re-display commercial? -1 always, 0 not this time, 1 this time
// 32views * 72lines * 2colors, plus what Timer B's 73rd line reads after view
// 31: on the ST the next thing in memory, which is _kolptr itself, and it holds
// &kolors[31] then. The value is where TOS loaded the program: $0003B6DA is
// Hatari's TOS 1.62 / 1 MB run of FUJIBOIN.PRG, the one the references come from.
static u16 kolors[33][144]; // [32][0..1] set in boot(): zero statics stay out of the data segment
#define KOLPTR_SPILL_HI 0x0003
#define KOLPTR_SPILL_LO 0xB6DA
static u16 rnbow[512];      // 512 colors
static unsigned fpos;       // the file position in FUJIBOIN.D8A (fhandle)

static const u16 couleurs[5][10] = {
/* color table to fade title screen to red and white... */
  {0x777, 0x766, 0x056, 0x056, 0x700, 0x700, 0x740, 0x740, 0x005, 0x005},
  {0x777, 0x755, 0x256, 0x245, 0x722, 0x700, 0x752, 0x730, 0x225, 0x204},
  {0x777, 0x744, 0x466, 0x434, 0x744, 0x700, 0x764, 0x720, 0x446, 0x403},
  {0x777, 0x722, 0x667, 0x622, 0x766, 0x700, 0x776, 0x710, 0x667, 0x602},
  {0x777, 0x700, 0x777, 0x700, 0x777, 0x700, 0x777, 0x700, 0x777, 0x700}
};

// The palette the desktop leaves (TOS's low-res default): Setcolor(i,-1).
static const u16 TOS_PALETTE[16] = {
    0x777, 0x700, 0x070, 0x770, 0x007, 0x707, 0x077, 0x555,
    0x333, 0x733, 0x373, 0x773, 0x337, 0x737, 0x377, 0x000};

static const int
  left[]=
    {0,0,0,1,1,1,2,2,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3},
  right[]=
    {6,6,6,6,6,6,6,6,6,5,5,5,5,6,6,7,7,7,8,8,8,9,9,9,9,10,10,10,10,10,10,10},
  bot[]={
    88,89,89,90,90,90,91,91,91,91,91,91,91,90,90,90,
    89,89,88,88,87,86,86,85,84,83,84,85,86,86,87,88};
static int work;             // flag: current work screen (0,1)
static const u8 *pix[32];    // pointers to 32 views of fuji
static const u8 *titlepic;   // 6800 bytes for title pic
static u16 barkolor[32];
static u16 savepalette[16];

// Fread(fhandle, n, ...): the next n bytes of FUJIBOIN.D8A.
static const u8 *fread_d8a(unsigned n) {
    const u8 *p = D8A + fpos;
    fpos += n;
    return p;
}

// --- the keyboard: Bconstat(2) / Bconin(2) --------------------------------
#define KEYQ 64
static u8 keyq[KEYQ]; // the ASCII byte Bconin(2)&255 returns
static unsigned keyq_head, keyq_tail;
static int want_menu; // Escape, or the program ended: back to the menu

static int bconstat(void) { return keyq_head != keyq_tail; }
static int bconin(void) {
    while (!bconstat()) {} // never reached: every caller checks bconstat() first
    const u8 k = keyq[keyq_tail];
    keyq_tail = (keyq_tail + 1) % KEYQ;
    return k;
}
static void keypress(u8 ascii) {
    const unsigned next = (keyq_head + 1) % KEYQ;
    if (next != keyq_tail) { keyq[keyq_head] = ascii; keyq_head = next; } // a full ST buffer drops keys too
}

// --- drawing ---------------------------------------------------------------
static void clear(int u0, int v0, int u1, int v1) {
/*      clear a rectangle
 *      u0,u1 in xpixels/16, v0,v1 in ypixels
 */
  kleer(screen[work], (u0<<3) + v0*160, 80 - ((u1 - u0 + 1) << 2), v1-v0, u1-u0);
}

static void v_bar(int x0, int y0, int x1, int y1, u8 color) { // VDI v_bar, replace mode
  for (int y = y0; y <= y1; y++)
    for (int x = x0; x <= x1; x++) screen[0][y * ST_W + x] = color;
}

static void drawgrid(void) {
/*      Guess what this does..
 */
  int pxy[4],i,j,k;
  for( i=0; i<3; i++ ){
    for( j=0; j<4; j++ ){
      pxy[0] = j * 64 + 32; pxy[1] = i * 50 + 25;
      pxy[2] = pxy[0]+31; pxy[3] = pxy[1]+24;
      v_bar( pxy[0], pxy[1], pxy[2], pxy[3], GRID );
      for( k=0; k<2; k++ ){
        pxy[k+k] += 32; pxy[k+k+1] += 25;
      }
      v_bar( pxy[0], pxy[1], pxy[2], pxy[3], GRID );
    }
  }
}

static void movit(int x, int y) {
/*      Move the fuji.
 *      Move fuji image into the current work screen
 *      at the proper x,y location (image # depends on x).
 *      Clear out leftovers from last move.
 */
  int view,disp,srcinc,dstinc,newtop,newbot,newleft,newright;
  static int oldtop[]={999,999},oldbot[]={0,0},oldleft[]={999,999},oldright[]={0,0};
  view = x & 31; disp = ( x>>5 ) << 2;
  newtop = y;
  newbot = y + bot[view]; if( newbot>MAXBOT ) newbot = MAXBOT;
  newleft = left[view] + disp; newright = right[view] + disp;
  if( newright<=MAXRIGHT ){
    srcinc = 0;
  }else{
    srcinc = (newright - MAXRIGHT) * 3; newright = MAXRIGHT;
  }
  dstinc = 80 - ((newright - newleft + 1) << 2);
  moov( pix[view], screen[work], (newleft<<3) + y*160, srcinc, dstinc,
    newbot-newtop, newright-newleft );
  --newtop; ++newbot; --newleft; ++newright;

  if( newtop > oldtop[work] )
    clear( oldleft[work], oldtop[work], oldright[work], newtop );
  oldtop[work] = newtop;
  if( newbot < oldbot[work] )
    clear( oldleft[work], newbot, oldright[work], oldbot[work] );
  oldbot[work] = newbot;
  if( newleft > oldleft[work] )
    clear( oldleft[work], oldtop[work], newleft, oldbot[work] );
  oldleft[work] = newleft;
  if( newright < oldright[work] )
    clear( newright, oldtop[work], oldright[work], oldbot[work] );
  oldright[work] = newright;
}

#define KKK     512
static void scrollkolors(int view) {
/*      Move the appropriate part of the rainbow table
 *      into the color table for the current view
 */
  static int irnbow=0; /* rainbow index: gets decremented so rainbow scrolls */
  int i, j = irnbow;
  for( i=0; i<72; i++ ){
    kolors[view][i<<1] = rnbow[j++];
    if( j == KKK ) j = 0;
  }
  if( irnbow == 0 ) irnbow = KKK;
  irnbow--;
}

#define NUMSHADES       19
static u16 shade(int s) { /* s in 0..99 */
  static const u16 shades[]={
      0x003, 0x113, 0x114, 0x115, 0x116, 0x117, 0x027, 0x037, 0x047,
      0x057, 0x157, 0x267, 0x367, 0x377, 0x477, 0x577, 0x677, 0x677, 0x777};
  return( shades[ (s*NUMSHADES)/100 ] );
}

static void setrnbow(void) {
/*      Setup rnbow array with 512 colors. Red component multiplied by 3
 *      for a little more variety in the rainbow.
 */
  int r,g,b,n=0;
  for( r=0; r<8; r++ )
    for( g=0; g<8; g++ )
      for( b=0; b<8; b++ )
        rnbow[ n++ ] = (u16)(((r*3)&7)*256 + b*16 + g);
}

static void setkolors(void) {
/*      Setup kolor array: 2304 bytes from file (generated by FUJISHAD),
 *      32view * 72lines; each byte to a color word (0-> dk. blue, 255-> lt. blue).
 */
  int iz = 0, view = 25, i, j;
  const u8 *z = fread_d8a(2304L);
  for( i=0; i<32; i++ ){
    barkolor[view] = shade( (z[iz]*100)/512 );
    for( j=0; j<72; j++ ){
      kolors[view][j+j+1] = shade( (z[iz++]*100)/256 );
    }
    if( ++view == 32 ) view = 0;
  }
  kolors[26][1] = couleurs[0][1];       /* !!! */
}

// --- the blocking half: every function below waits for VBLs ----------------
static int pt_titlecolor(int n) {
/*      Set title colors: use nth row of couleurs */
  static int lc, i;
  PT_BEGIN(lc);
  for( i=0; i<10; i++ ) setcolor( i+6, couleurs[n][i] );
  kolors[26][1] = couleurs[n][1];       /* !!! */
  for( i=0; i<3; i++ ){
    scrollkolors( 25 ); PT_YIELD(lc);
  }
  PT_END(lc);
}

static int pt_fadein(void) {
  static int lc, i;
  PT_BEGIN(lc);
  for( i=3; i>=0; i-- ) PT_CALL(lc, pt_titlecolor( i ));
  PT_END(lc);
}

static int pt_fadeout(void) {
  static int lc, i;
  PT_BEGIN(lc);
  for( i=1; i<=4; i++ ) PT_CALL(lc, pt_titlecolor( i ));
  PT_END(lc);
}

static int pt_settitle(void) {
/*      Put up commercial in work screen: 85 lines of 10 groups at (80,105). */
  static int lc;
  PT_BEGIN(lc);
  PT_CALL(lc, pt_titlecolor( 4 ));
  for (int i = 0; i < 85; i++) {
    for (int g = 0; g < 10; g++) {
      const u8 *s = titlepic + (i * 10 + g) * 8;
      u8 *d = screen[work] + (105 + i) * ST_W + 80 + g * 16;
      for (int b = 0; b < 16; b++) {
        const int k = 15 - b;
        d[b] = (u8)((be16(s) >> k & 1) | (be16(s + 2) >> k & 1) << 1 |
                    (be16(s + 4) >> k & 1) << 2 | (be16(s + 6) >> k & 1) << 3);
      }
    }
  }
  PT_END(lc);
}

static int pt_iniz(void) { /* initializer */
  static int lc;
  int i, j, prev;
  PT_BEGIN(lc);
  setcolor( 0, 0x777 );                 /* white */
  setcolor( GRID, 0x700 );              /* red */
  setcolor( SHADOW, 0x444 );            /* grey */
  setcolor( SHADOW|GRID, 0x400 );       /* not-so red */
  drawgrid();
  titlepic = fread_d8a( 6800L );        /* gettitle() */
  PT_CALL(lc, pt_settitle());
  PT_CALL(lc, pt_fadein());

  pix[25] = fread_d8a( 109596L );       /* fujistuff */
  for( j=1; j<32; j++ ){
    i=(j+25)&31; prev=(i-1)&31;
    pix[i]=pix[prev]+(right[prev]-left[prev]+1)*6*(bot[prev]+1);
  }
  fujiy = 0;
  setrnbow(); setkolors();
  for (i = 0; i < FB_BYTES; i++) screen[1][i] = screen[0][i]; /* copyscreen */
  PT_END(lc);
}

static int pt_intro(void) {
/*      Introduction. Leave fuji scrolling for 300 jiffies, fade out title. */
  static int lc, i;
  PT_BEGIN(lc);
  work = 0;
  fflag = 1;            /* start with rainbow face */
  fujiy = 15;
  kolptr = kolors[25];  /* fuji view 25 at middle of screen */
  movit( 57, 15 );
  for( i=0; i<300; i++ ){
    scrollkolors( 25 );
    PT_YIELD(lc);
  }
  PT_CALL(lc, pt_fadeout());
  clear( 5, 105, 14, 189 );
  work = 1;
  clear( 5, 105, 14, 189 );
  if( bconstat() ){  /* key pressed => always advertise */
    bconin(); advertising = -1;
  }
  PT_END(lc);
}

static int qui_ret;
static int pt_qui(void) {
/*      check qui-board: space bar returns -1; a function key waits until
 *      another key is pressed; any other key sets the advertising flag.
 */
  static int lc, key;
  PT_BEGIN(lc);
  qui_ret = 0;
  if( bconstat() ){
    if( advertising == 0 ) advertising = 1;
    if( (key = (bconin()&255)) == ' ' ) qui_ret = -1;
    if( key == 0 ){     /* fn key... */
      while( bconstat() == 0 ) PT_YIELD(lc);      /* wait for key */
      bconin();
    }
  }
  PT_END(lc);
}

static void thud(void) { zm_request_song(THUD); } /* Giaccess( 0, 13|128 ) */

static int pt_boink(void) {
/*      Make the fuji bounce. */
  static int lc, i, x,
    dx,         /* dx=0: moving left, dx=1: right, dx=-1: straight down */
    p,          /* y=p^2, p counts up and down so fuji bounces parabolically */
    dp,         /* dp=1: p counts up (fuji falls) */
    drapeau,    /* a flag */
    boom,       /* noize flag */
    y, view;
  PT_BEGIN(lc);
  p=0; dp=1; drapeau=1; boom=0;
  x = 57; dx = -1;
  for(;;){
    PT_CALL(lc, pt_qui());
    if( qui_ret != 0 ) break;  /* key not pressed... */
    y=15+(110 * p * p)/1600;
    view = x & 31;
    movit( x, y );
    scrollkolors( view );
    if( boom ){
      boom = 0; thud();
    }
    drapeau = (!drapeau) && (x==57) && (p==0) && advertising;
    if( dx == 1 ){
      if( ++x==114 ){ dx=0; boom = 1; }
    }else if( dx == 0 ){
      if( --x==0 ){ dx=1; boom = 1; }
    }
    if( dp ){
      if( ++p==40 ){/* hitting bottom? */
        dp=0; boom = 1;
        if( dx < 0 ){/* falling straight down? */
          dx = 0;
          setcolor( FARSIDE, shade(10) );/* set far side color to a dk blue */
          setcolor( FARSIDE|GRID, shade(10) );
        }
      }
    }else{
      if( --p==0 ) dp=1;
    }
    physbase = screen_fb[work];         /* these statements     */
    if( view==9 ) fflag ^= 1;           /* should all execute   */
    fujiy = y;                          /* within the same      */
    kolptr = kolors[view];              /* video frame (i.e. no */
    setcolor( BARSIDE, barkolor[view] );/* VBLANK in between    */
    setcolor( BARSIDE|GRID, barkolor[view] );
    kolbak = kolors[(view+16)&31][1];
    PT_YIELD(lc);        /* vsync: wait for vblank. */

    if( drapeau ){
      if( advertising == 1) advertising = 0;
      PT_CALL(lc, pt_titlecolor( 4 ));
      PT_CALL(lc, pt_settitle());
      PT_CALL(lc, pt_fadein());
      for( i=0; i<300; i++ ){
        scrollkolors( view );
        PT_YIELD(lc);
      }
      PT_CALL(lc, pt_fadeout());
      dx = -1; x = 57;
      clear( 5, 105, 14, 189 );
    }
    work ^= 1;
  }
  physbase = screen_fb[0];
  PT_END(lc);
}

static int pt_main(void) {
  static int lc;
  int i;
  PT_BEGIN(lc);
  physbase = screen_fb[0];                     /* Setscreen(-1L,-1L,0): lorez */
  for (i = 0; i < FB_BYTES; i++) screen[0][i] = 0;    /* v_clrwk */
  for( i=0; i<16; i++) savepalette[i] = st_color[i];
  PT_CALL(lc, pt_iniz());  /* initialize */
  ints_on = 1;             /* enable interrupts */
  PT_CALL(lc, pt_intro()); /* put up title */
  /* soundiniz(): the registers go with each thud, see thud.s */
  PT_CALL(lc, pt_boink()); /* do the bounce... */
  zm_stop_song();          /* soundoff() */
  ints_on = 0;             /* turn off interrupts */
  for (i = 0; i < FB_BYTES; i++) screen[0][i] = 0;    /* v_clrwk */
  for( i=0; i<16; i++) setcolor( i, savepalette[i] ); /* Setpallete */
  want_menu = 1;           /* say good-night, Gracie */
  PT_END(lc);
}

// --- the cart ---------------------------------------------------------------
static int finished;

__attribute__((export_name("boot")))
void boot(void) {
    video_base = hwVideoBase();
    screen[0] = io(OFF_VRAM);
    screen[1] = io(OFF_VRAM + FB_BYTES);
    screen_fb[0] = OFF_VRAM;
    screen_fb[1] = OFF_VRAM + FB_BYTES;
    physbase = screen_fb[0];
    kolors[32][0] = KOLPTR_SPILL_HI;
    kolors[32][1] = KOLPTR_SPILL_LO;
    for (int i = 0; i < 16; i++) setcolor(i, TOS_PALETTE[i]);
    for (int i = 0; i < FB_BYTES; i++) screen[0][i] = 0;
    // Timer B: the plane's HBL, once a line. Position = the end of the 320
    // displayed pixels, where the MFP counts the line (display enable drops).
    *(u16 *)io(REG_FB_HBL_ID) = 1;
    *(u16 *)io(REG_FB_HBL_POS) = ST_W;
}

// One machine tick = one VBL: run the program up to its next xbios(37), then
// the VBL interrupt. The machine draws the frame after this returns.
__attribute__((export_name("frame")))
void frame(float dt) {
    (void)dt; // paced by ticks, not time: see TIMING above
    if (zm_tvnoise_frame()) return; // a channel change: snow first
    if (!finished) finished = pt_main();
    vblank();
}

__attribute__((export_name("hblDispatch")))
void hblDispatch(u32 id, u32 plane, u32 line, u32 x) {
    (void)id; (void)plane; (void)x;
    if (zm_tvnoise_hbl()) return;
    timer_b(line);
}

// Keys reach Bconin as their ASCII byte. The host's private-use codes are the
// keys with no ASCII on an ST (F1-F10, Help, Undo...): Bconin(2)&255 == 0.
#define K_ESC 0xE012u
__attribute__((export_name("key")))
void key(u32 cp) {
    if (cp == K_ESC) { want_menu = 1; return; }
    keypress(cp < 0x80 ? (u8)cp : 0);
}

// The arrows come as directions (0..3), and have no ASCII either. Fire (5) is
// Space or Enter, which key() already delivered.
__attribute__((export_name("input")))
void input(u8 dir) { if (dir <= 3) keypress(0); }

__attribute__((export_name("pollCartRequest")))
int pollCartRequest(void) {
    if (!want_menu) return 0;
    want_menu = 0;
    return -1; // the menu disk
}

__attribute__((export_name("isPlaneEnabled")))
_Bool isPlaneEnabled(u8 id) { return id == 0; }

__attribute__((export_name("skipBoot")))     void skipBoot(void) { zm_tvnoise_stop(); }
__attribute__((export_name("setShadeMode"))) void setShadeMode(u32 m) { (void)m; }
__attribute__((export_name("pointer")))      void pointer(int x, int y, u32 b) { (void)x; (void)y; (void)b; }
