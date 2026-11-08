
enum DisplayCodes { DISPLAY_INIT_CODE=2, DISPLAY_RUN_CODE=0, DISPLAY_REFRESH_CODE=1, DISPLAY_EXITDIALOG_CODE=3 };
enum DisplayModes { TUI_MODE_MONOCHROME = 1, TUI_MODE_COLOR = 2 };


//#define ZOOM_DEFAULT 2 //3 //2 //3 //values: 1..X //use only 2x (for standard 640x480 resolution), otherwise some OS bugs with fullscreen  //moved to SIDwizard.h
#define ZOOM_MIN 1 //2 //1
#define ZOOM_MAX 4
#define SPRITE_HEIGHT 21
#define SPRITE_WIDTH  24
#define SPRITE_BYTEWIDTH 3 //bytes
#define SPRITE_SIZE (SPRITE_HEIGHT*SPRITE_BYTEWIDTH) //bytes
#define SPRITE_MEMALIGN 0x40
#define CURSORSPRITE_ADDRESS 0xD900
#define ORDERLISTCURSOR_ADDRESS 0xDB00
#define TOPSPRITE_ADDRESS 0xD940
#define BOTTOMSPRITE_ADDRESS 0x0400
#define BORDER (SPRITE_HEIGHT+2) //16 //20 //for top and bottom
#define FIRSTROW_RASTER 0x30
#define ORDERLIST_RASTER 0x100
#define FIRSTCOLUMN_RASTER 0x18
#define INSCREEN_RASTER 0x80
//#define ROW26_RASTER    0xF6
#define SIDEBORDER_WIDTH 10 //8 //3
#define WINWIDTH_DEFAULT (SCREENWIDTH*CHARWIDTH_DEFAULT) //use only standard resolution, otherwise some OS bugs with fullscreen
#define WINHEIGHT_DEFAULT ( ((SCREENHEIGHT+0)*CHARHEIGHT+BORDER*2) * ZOOM_DEFAULT ) //use only standard resolution, otherwise some OS bugs with fullscreen
#define BITSPERPIXEL 32
#define BYTESPERPIXEL (BITSPERPIXEL/8)
#define SCANLINE_FADE 0.1 //0.26 //values: 0.0...0.5
#define BLUR_SOFTNESS 0.0 //1.0  //values: 1.0 .. X (or 0 to disable)
#define BRIGHTNESS 1.5
#define SPRITEBLUR 2.0
#define COLOR_AMOUNT 16
#define COLOR_MAX (COLOR_AMOUNT-1)
#define COLOR_MASK (COLOR_MAX)
#define CHARSET_AMOUNT 2
#define BGCOLOR 0 //9
#define GUIMODE_BGCOLOR 0x081010
#define GUIMODE_HEADER_BGCOLOR 0x919191
#define BUTTONBGCOLOR_R 0x30
#define BUTTONBGCOLOR_G 0x20
#define BUTTONBGCOLOR_B 0x10
#define BUTTONFGCOLOR_R 0x90
#define BUTTONFGCOLOR_G 0x80
#define BUTTONFGCOLOR_B 0x70
#define BUTTGAPCOLOR_R 0x08
#define BUTTGAPCOLOR_G 0x10
#define BUTTGAPCOLOR_B 0x18
#define ORDERLIST_RASTERBAR_SEPARATOR_COLOR 0xF
//#define FGCOLOR 13
//#define SCREENWIDTH 40
#define SCREENHEIGHT (25+1) //25  //row26 added (a VIC-trick)
#define VRAM_SIZE (SCREENWIDTH*SCREENHEIGHT)
#define VRAM_PADDING 0x400
#define CHARSET_SIZE 0x800
#define BUTTONCHARSET_SIZE 0x400
#define CHARAMOUNT (CHARSET_SIZE/CHARHEIGHT)
#define BUTTONCHARAMOUNT (BUTTONCHARSET_SIZE/CHARHEIGHT)
#define CHARSETWIDTH 32
#define SMALLCHARSET_OFFSET (CHARSET_SIZE)
#define VICBANK_SIZE 0x4000
//#define VICBANKSEL_ADDRESS 0xDD00
//#define VRAMSEL_ADDRESS 0xD018
//#define SPRITEENABLE_ADDRESS 0xD015
#define CHARSET_ADDRESS 0x1000 //0xD000
//#define CRAM_ADDRESS    0xD800
#define VRAM_ADDRESS    0xE000
#define CHARWIDTH 8  //datapixels
#define CHARHEIGHT 8 //datapixels
#define CHARWIDTH_DEFAULT (ZOOM_DEFAULT*CHARWIDTH)
#define CHARWIDTH_MAX (ZOOM_MAX*CHARWIDTH)
#define CHARHEIGHT_DEFAULT (ZOOM_DEFAULT*CHARHEIGHT)
#define CHARHEIGHT_MAX (ZOOM_MAX*CHARHEIGHT)

#ifndef SIDMAKER
 #define GUI_HEADERINFO_X  189  //200   //(includes playertype-letter too on the left)
 #define GUI_HEADERINFO_Y  1
 #define GUI_HEADERINFO_WIDTH   (CHARWIDTH * 11 + 11)
 #define GUI_HEADERINFO_HEIGHT  (CHARHEIGHT * 2 + 4)
 #define GUI_PATTERN_HEADERS_X  (/*SIDEBORDER_WIDTH +*/ 0)
 #define BORDERHEIGHT  BORDER
 #define GUI_PATTERN_HEADERS_Y  (BORDERHEIGHT - CHARHEIGHT + 1)
 #define GUI_PATTERN_TRACK_CHARSPACING 10
 #define GUI_PATTERN_TRACK_SPACING (CHARWIDTH * GUI_PATTERN_TRACK_CHARSPACING)
  #define GUI_TRACKINFO_WIDTH   (GUI_PATTERN_TRACK_SPACING * SID_CHANNEL_AMOUNT - 2)
 #define GUI_TRACKINFO_HEIGHT  (CHARHEIGHT-2)
 #define GUI_SWEEPBARS_X 241
 #define GUI_SWEEPBARS_Y 15
 #define GUI_SWEEPBARS_WIDTH 42

 #define OSCILLOSCOPE_X (36*CHARWIDTH+2)
 #define OSCILLOSCOPE_Y 3
 #define OSCILLOSCOPE_WIDTH 24
 #define OSCILLOSCOPE_HEIGHT 15
 #define OSCILLOSCOPE_BOTTOM_Y (OSCILLOSCOPE_Y + OSCILLOSCOPE_HEIGHT)
 #define SCOPEDATA_COLOR 0x20FF90
 #define SCOPE_BGCOLOR 0x011008

 #define VOLUMEBAR_Y 3
 #define VOLUMEBAR_WIDTH (SIDEBORDER_WIDTH-2*3)
 #define VOLUMEBAR_HEIGHT 16
 #define VOLUMEBAR_SCALE_MARGIN 2
 #define VOLUMEBAR_BACKGROUND_COLOR 0x103060
 #define VOLUMEBAR_NOSOUND_WARN_COLOR 0xC03020
 #define VOLUMEBAR_SCALE_COLOR 0x80E0F0

 #define PIANOROLL_TOGGLE_BUTTON_CHARWIDTH 2 //1 //#define PIANOROLL_TOGGLE_BUTTON_WIDTH 10
 //#define PIANOROLL_TOGGLE_BUTTON_HEIGHT 10
 #define PIANO_KEYBOARD_OCTAVE_COUNT 8 //9 //SID's octave count
 #define PIANO_WHITE_KEYS_PER_OCTAVE 7
 #define PIANO_BLACK_KEYS_PER_OCTAVE 5
  #define PIANO_KEYS_PER_OCTAVE (PIANO_WHITE_KEYS_PER_OCTAVE + PIANO_BLACK_KEYS_PER_OCTAVE) //12
  #define PIANO_WHITE_KEY_COUNT (PIANO_WHITE_KEYS_PER_OCTAVE * PIANO_KEYBOARD_OCTAVE_COUNT) //7*8=56 //12*8=96 //88
  #define PIANO_KEY_COUNT (PIANO_KEYS_PER_OCTAVE * PIANO_KEYBOARD_OCTAVE_COUNT) //12*8=96 //88
 #define PIANOROLL_FRACTIONAL_BITS 8 //4
 #define PIANO_WHITE_KEY_COLOR 0xFCF8F0
 #define PIANO_BLACK_KEY_COLOR 0x081030
 #define PIANO_KEYGAP_COLOR 0x040201
 #define PIANOROLL_X_START 1
 #define PIANOROLL_CHARWIDTH 28
 #define PIANOROLL_X_END (PIANOROLL_X_START + PIANOROLL_CHARWIDTH) //+ 1 //30 //29  //+1 to ensure deletion of vibratos/slides at right-edge
 #define PIANOROLL_Y_END 25
 #define PIANOROLL_GRID_COLOR 0X808080 //0x606060 //0x808080 //0x404040
#endif  //ifndef SIDMAKER

#if (ENABLED_TUI)
#define TUI_SCREENWIDTH 80  //the standard 80-column character screen (hopefully supported on most platforms)
#define TUI_SCREENHEIGHT (SCREENHEIGHT-1) //25 (unlike tricked 26-row on C64 in SID-Wizard)
#define TUI_INSCREEN_X ( (TUI_SCREENWIDTH - SCREENWIDTH) / 2 )
#define TUI_ORDERLIST_X 2
#define TUI_ORDERLIST_Y 5
#define TUI_ORDERLIST_CHANNEL_PADDING 4
#define TUI_ORDERLIST_CHANNEL1_PADDING 5 //first channel's position to orderlist-numbering
#define C64_ORDERLIST_WIDTH 0x28
#define ORDERLIST_DISPLAYED_ENTRY_AMOUNT (C64_ORDERLIST_WIDTH/2) //0x14
 #define TUI_ORDERLIST_HEIGHT (C64_ORDERLIST_WIDTH/2) //0x14
#define ORDERLIST_HEADER_X (TUI_ORDERLIST_X+TUI_ORDERLIST_CHANNEL1_PADDING-6)
#define ORDERLIST_HEADER_Y (TUI_ORDERLIST_Y-4)
//#define TUI_ORDERLIST_DATA_COLOR 1 //actually colortheme-dependent!
#define TUI_LOGO_X (TUI_INSCREEN_X + SCREENWIDTH + 1)
#define TUI_LOGO_Y 1
#define TUI_LOGO_COLOR 6 //12
#define TUI_SCOPE_X (TUI_INSCREEN_X + SCREENWIDTH + 1)
#define TUI_SCOPE_Y (TUI_LOGO_Y+2)
#define TUI_SCOPE_WIDTH (TUI_SCREENWIDTH-1 - TUI_SCOPE_X)
#define TUI_SCOPE_HEIGHT (TUI_SCOPE_WIDTH/2-2)
#define TUI_SCOPE_BOTTOM (TUI_SCOPE_Y + TUI_SCOPE_HEIGHT - 1)
#define TUI_SCOPE_BACKGROUND_COLOR 0 //2 //9  //not operational on all terminals, and red looks ugly anyway
#define TUI_SCOPE_SIGNAL_COLOR 13 //3 //with bold/bright set  //13 //7 //1 //13 //5 //13 //10 //not operational on all terminals
#define TUI_SCOPE_SUBPOSITION_Y_BITS 3
#define TUI_SCOPE_SUBPOSITION_Y_RANGE (1 << TUI_SCOPE_SUBPOSITION_Y_BITS)
#define TUI_SCOPE_PHOSPHOR_DECAY_COLOR 6 //9 //11 //9 //6 //11 //9 //5 //9 //5
//#define TUI_SCOPE_PHOSPHOR_DECAY_TIME 4 //*20ms periods
#define TUI_SCOPE_OVERSAMPLING 2  //shouldn't be bigger than ZOOM_MAX  //actually the code (and char-data and ASCII charset) is only able to display 2x oversampling horizontally
#define TUI_SWEEPBARS_X (TUI_SCOPE_X)
#define TUI_SWEEPBARS_Y (TUI_SCOPE_BOTTOM+2)
#define TUI_SWEEPBARS_HEIGHT 4
#define TUI_SWEEPBAR_WIDTH 16 //(TUI_SCOPE_WIDTH-2)
#define TUI_VOLUMEBAR_WIDTH 8
#define TUI_COMMONINFO_X (TUI_INSCREEN_X + SCREENWIDTH + 2)
#define TUI_COMMONINFO_Y (TUI_SWEEPBARS_Y+TUI_SWEEPBARS_HEIGHT+1) //(TUI_SCOPE_Y + TUI_SCOPE_HEIGHT + 5)
#define TUI_SETTING_BACKGROUND_COLOR 2
#define TUI_PROGRESS_X (TUI_SCREENWIDTH-1) //(TUI_INSCREEN_X + SCREENWIDTH) //(TUI_COMMONINFO_X-1)  //18
#define TUI_PROGRESS_Y (TUI_SCREENHEIGHT-1) //0 //(TUI_COMMONINFO_Y+0) //2
#endif

#if (ENABLED_SDL)

#include "buttoncharset.h"
#include "../resources/chargen.h"
#include "../resources/CharGen-16x16.h"
#include "../resources/CharGen-24x24.h"
#include "../resources/CharGen-32x32.h"
#include "../resources/SW-charset-16x16.h"
#include "../resources/SW-charset-24x24.h"
#include "../resources/SW-charset-32x32.h"

static char *mouse_xpm[] = {
"32 32 3 1 0 0",
"0	c #000000",
"1	c #FFFFFF",
" 	c None",
"00                              ",
"010                             ",
"01100                           ",
"011100                          ",
"0111100                         ",
"01110100                        ",
"010111100                       ",
"0111111100                      ",
"01111111100                     ",
"01111111100                     ",
"01111111100                     ",
"01111111000                     ",
"0011111000                      ",
" 00000100                       ",
"  000010                        ",
"      010                       ",
"      010                       ",
"       01                       ",
"         1                      ",
"                                ",
"                                ", //       ",
"                                ",
"                                ",
"                                ",
"                                ",
"                                ",
"                                ",
"                                ",
"                                ",
"                                ",
"                                ",
"                                "
};


//#include "../resources/SID-Wizard-icon.xpm"
#include "../resources/SW-icon-16x16.xpm"


#ifndef SIDMAKER

#include "../resources/SIDwizard-SplashLogo.bmp.cmp.h"  /* #include "../resources/SIDwizard-SplashLogo.xpm" */
static unsigned char* SIDwizard_SplashLogo_bmp = NULL;  //will point to decompressed BMP splash-logo

#include "../resources/SW-header-GUI.xpm"
static char* *SW_header_GUI_xpm = SW_xpm;
#include "../resources/SWheader2x.bmp.cmp.h"  //#include "../resources/SWheader2x.xpm"
static unsigned char *SWheader2x_bmp = NULL;  //static char* *SWheader2x_xpm = NULL;  //will point to decompressed XPM header-logo
#include "../resources/SWheader3x.bmp.cmp.h"  //#include "../resources/SWheader3x.xpm"
static unsigned char *SWheader3x_bmp = NULL;  //static char* *SWheader3x_xpm = NULL;  //will point to decompressed XPM header-logo
#include "../resources/SWheader4x.bmp.cmp.h"  //#include "../resources/SWheader4x.xpm"
static unsigned char *SWheader4x_bmp = NULL;  //static char* *SWheader4x_xpm = NULL;  //will point to decompressed XPM header-logo

#endif //end of ifndef SIDMAKER


/*#if (SIDAMOUNT>1)
 #define OPTIONAMOUNT 5
#else
 #define OPTIONAMOUNT 4
#endif*/

static byte ButtonVRAM[]=
 "                                  "
//#if (SIDAMOUNT>1)
 "       "
 #ifndef SIDMAKER
        "      "
 #endif
/*#else
 #ifndef SIDMAKER
  "      "
 #endif
#endif*/
;
byte PrevButtonVRAM[sizeof(ButtonVRAM)]="";

const  byte* ButtonTexts[]=
{//(byte*)
 "zoom1  hqborder   sid8580  sidhq  "
//#if (SIDAMOUNT>1)
 //(byte*)
 "  mono "
 #ifndef SIDMAKER
 //(byte*)
        " MIDI:"
 #endif
/*#else
 #ifndef SIDMAKER
 //(byte*)
  " MIDI:"
 #endif
#endif*/
,//(byte*)
 "zoom2 lofiborder  sid6581 sidlight"
//#if (SIDAMOUNT>1)
 //(byte*)
 "  wide "
 #ifndef SIDMAKER
 //(byte*)
        " MIDI:"
 #endif
/*#else
 #ifndef SIDMAKER
 //(byte*)
 " MIDI:"
 #endif
#endif*/
,//(byte*)
 "zoom3                             "
//#if (SIDAMOUNT>1)
 //(byte*)
 "       "
/*#else
 #ifndef SIDMAKER
 //(byte*)
 " MIDI:"
 #endif
#endif*/
,//(byte*)
 "zoom4                             "
//#if (SIDAMOUNT>1)
 //(byte*)
 " stereo"
/*#else
 #ifndef SIDMAKER
 //(byte*)
 " MIDI:"
 #endif
#endif*/
};

//static byte ButtonText3[]="zoom4                                    ";
static byte ButtonTops[]=
{ 0,    6,          18,     26,
//#if (SIDAMOUNT>1)
  35,
 #ifndef SIDMAKER
         42
 #endif
/*#else
 #ifndef SIDMAKER
  35
 #endif
#endif*/
};
static byte ButtonBots[]=
{     4,         15,      24,      33,
//#if (SIDAMOUNT>1)
       40,
 #ifndef SIDMAKER
              46
 #endif
/*#else
 #ifndef SIDMAKER
      39
 #endif
#endif*/
};


static const byte palette[COLOR_AMOUNT][3] = { //pepto
 {0x00,0x00,0x00}, {0xFF,0xFF,0xFF}, {0x68,0x37,0x2b}, {0x70,0xa4,0xb2},
 {0x6f,0x3d,0x86}, {0x58,0x8d,0x43}, {0x35,0x28,0x79}, {0xb8,0xc7,0x6f},
 {0x6f,0x4f,0x25}, {0x43,0x39,0x00}, {0x9a,0x67,0x59}, {0x44,0x44,0x44},
 {0x6c,0x6c,0x6c}, {0x9a,0xd2,0x84}, {0x6c,0x5e,0xb5}, {0x95,0x95,0x95} };
static const unsigned int Palette[COLOR_AMOUNT] = {
 #define satur(value) ( (byte) ( ( ((((word)(value))&0xFFFF)<0xFF) ? (((byte)(value))&0xFF):0xFF ) & 0xFF ) )
 #define palToPal(R,G,B) ( 0xFF000000+(satur(R*BRIGHTNESS)<<16)+(satur(G*BRIGHTNESS)<<8)+satur(B*BRIGHTNESS) )  //#define palToPal(idx) ( 0xFF000000+(satur(palette[idx][0]*BRIGHTNESS)<<16)+(satur(palette[idx][1]*BRIGHTNESS)<<8)+satur(palette[idx][2]*BRIGHTNESS) )
 #define palToPalBlur(R,G,B) ( 0xFF000000+(satur(R*BRIGHTNESS/SPRITEBLUR)<<16)+(satur(G*BRIGHTNESS/SPRITEBLUR)<<8)+satur(B*BRIGHTNESS/SPRITEBLUR) )  //#define palToPalBlur(idx) ( 0xFF000000+(satur(palette[idx][0]*BRIGHTNESS/SPRITEBLUR)<<16)+(satur(palette[idx][1]*BRIGHTNESS/SPRITEBLUR)<<8)+satur(palette[idx][2]*BRIGHTNESS/SPRITEBLUR) )
 palToPal(0x00,0x00,0x00),palToPal(0xFF,0xFF,0xFF),palToPal(0x68,0x37,0x2b),palToPal(0x70,0xa4,0xb2),palToPal(0x6f,0x3d,0x86),palToPal(0x58,0x8d,0x43),palToPal(0x35,0x28,0x79),palToPal(0xb8,0xc7,0x6f), //palToPal(0),palToPal(1),palToPal(2),palToPal(3),palToPal(4),palToPal(5),palToPal(6),palToPal(7),
 palToPal(0x6f,0x4f,0x25),palToPal(0x43,0x39,0x00),palToPal(0x9a,0x67,0x59),palToPal(0x44,0x44,0x44),palToPal(0x6c,0x6c,0x6c),palToPal(0x9a,0xd2,0x84),palToPal(0x6c,0x5e,0xb5),palToPal(0x95,0x95,0x95) }; //palToPal(8),palToPal(9),palToPal(10),palToPal(11),palToPal(12),palToPal(13),palToPal(14),palToPal(15) };
static const unsigned int BlurPalette[COLOR_AMOUNT] = {
 palToPalBlur(0x00,0x00,0x00),palToPalBlur(0xFF,0xFF,0xFF),palToPalBlur(0x68,0x37,0x2b),palToPalBlur(0x70,0xa4,0xb2),palToPalBlur(0x6f,0x3d,0x8),palToPalBlur(0x58,0x8d,0x43),palToPalBlur(0x35,0x28,0x79),palToPalBlur(0xb8,0xc7,0x6f),  //palToPalBlur(0),palToPalBlur(1),palToPalBlur(2),palToPalBlur(3),palToPalBlur(4),palToPalBlur(5),palToPalBlur(6),palToPalBlur(7),
 palToPalBlur(0x6f,0x4f,0x25),palToPalBlur(0x43,0x39,0x00),palToPalBlur(0x9a,0x67,0x59),palToPalBlur(0x44,0x44,0x44),palToPalBlur(0x6c,0x6c,0x6c),palToPalBlur(0x9a,0xd2,0x84),palToPalBlur(0x6c,0x5e,0xb5),palToPalBlur(0x95,0x95,0x95) };  //palToPalBlur(8),palToPalBlur(9),palToPalBlur(10),palToPalBlur(11),palToPalBlur(12),palToPalBlur(13),palToPalBlur(14),palToPalBlur(15) };

static const unsigned int GUIpalette[COLOR_AMOUNT] = {
 0x000000, 0xFFFFFF, 0x52383d, 0x85a1a0, 0x684968, 0x607e5f, 0x34335e, 0xbdbb99,  //handmade with more concrete hues and less saturation
 0x5e4f3f, 0x443922, 0x9a7a86, 0x4e4e4e, 0x787878, 0xa1caa0, 0x707198, 0xaaaaaa
 //0x000000, 0xFFFFFF, 0x523d38, 0x859ba1, 0x5e4968, 0x677e5f, 0x342e50, 0xb7bd99,  //less colorful palette
 //0x5e513f, 0x3a351e, 0x836d68, 0x444444, 0x6b6b6b, 0xaac1a1, 0x6b6589, 0x949494
 //0x000000, 0xFFFFFF, 0x68372b, 0x70a4b2, 0x6f3d86, 0x588d43, 0x352879, 0xb8c76f,  //normal pepto palette
 //0x6f4f25, 0x433900, 0x9a6759, 0x444444, 0x6c6c6c, 0x9ad284, 0x6c5eb5, 0x959595
};


static byte* CharSetAddresses[CHARSET_AMOUNT+1] = { &cRSID_C64.ROMbanks[0x1800], &cRSID_C64.RAMbank[0xD000], &cRSID_C64.ROMbanks[0x1800] };

static const char GUIheaderInfoLeftNybbleToChar [] = {
 0xE8,0xE9,0xEA,0xEB,0xEC,0xED,0xEE,0xEF, 0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7
 //0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F  //too tall, active height should be 5, using orderlist left-right chars instead
};
static const char GUIheaderInfoRightNybbleToChar [] = {
 0x66,0x67,0x68,0x69,0x6A,0x6B,0x6C,0x6F, 0x71,0x72,0x73,0x74,0x76,0x77,0x78,0x79
 //0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F  //too tall, active height should be 5, using orderlist left-right chars instead
};


#endif //ENABLED_SDL


#if ENABLED_TUI

enum { COLOR_BRIGHT = 8, COLOR_ATTRIBUTE_BOLD = (COLOR_BRIGHT) /* would be useful for attron()/attroff(), but Is it the same as brightness? */ };
enum { RESTRICTED_COLORS = 0 *COLOR_AMOUNT, CURSOR_COLORS = RESTRICTED_COLORS, BACKGROUND_COLORS = 3 *COLOR_AMOUNT, CURSOR_STATE_AMOUNT = 3,
       }; //FULL_FOREGROUND_COLORS = (CURSOR_COLORS + 16*COLOR_AMOUNT) };

/*static const int TUIpaletteFullColor [COLOR_AMOUNT] = { //for foreground-colors (may be converted to brighter color, used depending on the terminal emulator having 8/16 colors or more)
//    0                    1                  2                   3                   4             5           6                    7
 COLOR_BLACK, COLOR_BRIGHT | COLOR_WHITE, COLOR_RED, COLOR_BRIGHT | COLOR_CYAN, COLOR_MAGENTA, COLOR_GREEN, COLOR_BLUE, COLOR_BRIGHT | COLOR_YELLOW,
//    8             9                     A                         B                   C                    D                           E                          F
 COLOR_YELLOW, COLOR_YELLOW, COLOR_BRIGHT | COLOR_RED, COLOR_BRIGHT | COLOR_BLACK, COLOR_WHITE, COLOR_BRIGHT | COLOR_GREEN, COLOR_BRIGHT | COLOR_BLUE, COLOR_BRIGHT | COLOR_WHITE
};*/  //forget it, terminals are wildly different and are barely following any standard, stick to restricted classical terminal color-set (8 colors guaranteed, mot time 16 are available by brightness/bold-bit)

static const int TUIpaletteRestricted [COLOR_AMOUNT] = { //for foreground-colors (may be converted to brighter color plus bold character)
//    0                    1                  2                   3                   4             5           6                    7
 COLOR_BLACK, COLOR_BRIGHT | COLOR_WHITE, COLOR_RED, COLOR_BRIGHT | COLOR_CYAN, COLOR_MAGENTA, COLOR_GREEN, COLOR_BLUE, COLOR_BRIGHT | COLOR_YELLOW,
//    8             9                     A                         B                                                                       C                         D                           E                          F
 COLOR_YELLOW, /*COLOR_RED*/COLOR_YELLOW, COLOR_BRIGHT | COLOR_RED, COLOR_GREEN/*COLOR_BLUE*//*COLOR_CYAN*/ /*COLOR_BRIGHT | COLOR_BLACK*/, COLOR_WHITE, COLOR_BRIGHT | COLOR_GREEN, COLOR_BRIGHT | COLOR_BLUE, COLOR_BRIGHT | COLOR_WHITE
};                                                                                               //avoid COLOR_BRIGHT|COLOR_BLACK as it gives black if A_BOLD is not shown as bright-black aka grey by the terminal

static const int TUIpaletteBackground [COLOR_AMOUNT] = { //character background-color has no 'bright' version on standard 16color (like xterm) consoles (but seemingly has on lxterminal/etc)
//    0                      1                             2           3                            4              5            6              7
 COLOR_BLUE/*COLOR_BLACK*/,  /*COLOR_BRIGHT|*/COLOR_WHITE, COLOR_RED,  /*COLOR_BRIGHT|*/COLOR_CYAN, COLOR_MAGENTA, COLOR_GREEN, COLOR_BLUE,  /*COLOR_BRIGHT|*/COLOR_YELLOW,
//    8          9                      A                                     B                                        C                                           D                                      E                            F
 COLOR_RED, /*COLOR_YELLOW*/COLOR_RED, /*COLOR_BRIGHT|*/COLOR_MAGENTA, COLOR_GREEN/*COLOR_CYAN*//*COLOR_BLUE*/, /*COLOR_BRIGHT|*/COLOR_CYAN/*COLOR_WHITE*/, /*COLOR_BRIGHT|*//*COLOR_GREEN*/COLOR_YELLOW, COLOR_GREEN/*COLOR_CYAN*/, COLOR_WHITE //substituting with one similar in luminance (and color) to C64 palette
};

static const char SelectedCursorColors [COLOR_AMOUNT] = { //to have the 2 custom colors directly after the black in termital with few color-pairs
// 0  1  2      3  4  5  6  7    8  9  A  B  C  D  E  F
   0, 3, 2,     3, 4, 5, 6, 7,   8, 9,10,11,12,13,14,15
};
static const char InvertedCursorColors [CURSOR_STATE_AMOUNT/*COLOR_AMOUNT*/] = { //to have the 2 custom colors directly after the black in termital with few color-pairs
// 0  1  2      3  4  5  6  7    8  9  A  B  C  D  E  F
// 3, 0, 2,     0, 5, 4, 7, 6,  14,13,10,15, 1, 9, 8,11
// 2, 1, 2, 0, 2, 2, 2, 1,   2, 2, 0, 2, 0, 1, 0, 1
   2, 0, 1
};
static const char RestrictedCursorColors [COLOR_AMOUNT] = { //for better cursor pulsation on restricted 8-color terminal
// 0  1  2  3  4  5  6  7    8  9  A  B  C  D  E  F
   0, 1, 2, 2, 2, 2, 0, 1,   2, 0, 2, 0, 2, 1, 2, 1
// 0, 1, 0, 2, 0, 0, 0, 1,   0, 0, 2, 0, 2, 1, 2, 1
};

static const char OppositeCursorColors [CURSOR_STATE_AMOUNT] [COLOR_AMOUNT] = { //non-inverted character foreground-color modification for given cursor-color (background) to be the opposite
// 0  1  2  3   4  5  6  7   8  9  A  B   C  D  E  F //cursor-color 'opposites' for colors of TUIpaletteRestricted (with 'bold'/'bright' bit) so character is always well seen
 { 1, 1, 2, 3,  4, 5, 6, 7,  8, 9,10,11, 12,13,14,15 }, //cursor-color 0 from RestrictedCursorColors[] - black (C64color==0) - darkest state of cursor
 { 0, 0, 2, 2,  2, 2, 6, 0,  0, 0, 0, 2,  2, 0, 2, 0 }, //cursor-color 1 from RestrictedCursorColors[] - cyan  (C64color==3) - brightest state of cursor
 { 0, 1, 3, 3,  4, 5, 6, 7,  0, 3,10, 3,  3, 3, 3, 0 }  //cursor-color 2 from RestrictedCursorColors[] - red   (C64color==2) - short middle state of cursor
};


enum { INVERT = 0x80, NONINVERTED_CHAR_MASK = (INVERT-1), NONINVERTED_CHAR_AMOUNT = (INVERT) };

static const byte PETSCIItoASCII [NONINVERTED_CHAR_AMOUNT] = { // [256] = {
 '@', 'a','b','c','d','e','f','g','h','i','j','k','l','m','n','o',
 'p','q','r','s','t','u','v','w','x','y','z', '[','£',']','^','<',

 ' ', '!','\"','#','$','%','&','\'','(',')','*','+',',','-','.','/',
 '0','1','2','3','4','5','6','7','8','9',':',';','<','=','>','?',

 '-', 'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
 'P','Q','R','S','T','U','V','W','X','Y','Z', '+','.','|','.','.',

 ' ','.','_','\"','_','|','.','|','.','.','|','.','.','\'',',','_',
 ',','.','.','.','|','|','|','.','.','_','*','.','.','\'','.','/',


 /*'.','.','.','.','.','.','.','.','.','.','.','.','.','.','.','.',
 '.','.','.','.','.','.','.','.','.','.','.','.','.','.','.','.',

 '.','.','.','.','.','.','.','.','.','.','.','.','.','.','.','.',
 '.','.','.','.','.','.','.','.','.','.','.','.','.','.','.','.',

 '.','.','.','.','.','.','.','.','.','.','.','.','.','.','.','.',
 '.','.','.','.','.','.','.','.','.','.','.','.','.','.','.','.',

 '.','.','.','.','.','.','.','.','.','.','.','.','.','.','.','.',
 '.','.','.','.','.','.','.','.','.','.','.','.','.','.','.','.'*/
};

static const byte SIDwizardCharToASCII [256] = {
 '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F',
 '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F',

 INVERT|' ', INVERT|'!', INVERT|'\"', INVERT|'#', INVERT|'$', INVERT|'%', INVERT|'&', INVERT|'\'', INVERT|'(', INVERT|')', INVERT|'#', INVERT|'+', INVERT|',', INVERT|'-', INVERT|'.', INVERT|'/',
 INVERT|'0', INVERT|'1', INVERT|'2', INVERT|'3', INVERT|'4', INVERT|'5', INVERT|'6', INVERT|'7', INVERT|'8', INVERT|'9', INVERT|':', INVERT|';', INVERT|'<', INVERT|'=', INVERT|'>', INVERT|'?',

 INVERT|'@', INVERT|'A', INVERT|'B', INVERT|'C', INVERT|'D', INVERT|'E', INVERT|'F', INVERT|'G', INVERT|'H', INVERT|'I', INVERT|'J', INVERT|'K', INVERT|'L', INVERT|'M', INVERT|'N', INVERT|'O',
 INVERT|'P', INVERT|'Q', INVERT|'R', INVERT|'S', INVERT|'T', INVERT|'U', INVERT|'V', INVERT|'W', INVERT|'X', INVERT|'Y', INVERT|'Z', '.', '.', '.', '.', '-',

        '-',        '.',        '.',        '.', INVERT|'A', INVERT|'D', INVERT|'F', INVERT|'1', INVERT|'L', INVERT|'^', INVERT|'V', INVERT|'i', INVERT|'T', INVERT|'y', INVERT|'~', INVERT|'<',
 INVERT|'-', INVERT|'^', INVERT|'_', INVERT|'S', INVERT|'C', INVERT|'O', INVERT|'c', INVERT|'H', INVERT|'R', INVERT|'T', INVERT|'C', INVERT|'h', INVERT|'T', INVERT|':', INVERT|' ', INVERT|'_',


 'C','C'/*'c'*/,'D','D'/*'d'*/,'E','F','F'/*'f'*/,'G','G'/*'g'*/,'A','v','B', INVERT|'S', INVERT|'t', INVERT|':', '~',
 '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F',

 '1','2','3','4','5','6','7','8','9','A','/','|','r','+','-','+',
 INVERT|'1',INVERT|'2',INVERT|'3',INVERT|'4',INVERT|'5',INVERT|'6',INVERT|'7',INVERT|'8',INVERT|'9','P','\\', '<','>', ' ','-','o',

 INVERT|'0', INVERT|'1', INVERT|'2', INVERT|'3', INVERT|'4', INVERT|'5', INVERT|'6', INVERT|'7', INVERT|'8', INVERT|'9', INVERT|'A', INVERT|'B', INVERT|'C', INVERT|'D', INVERT|'E', INVERT|'F',
 INVERT|'0', INVERT|'1', INVERT|'2', INVERT|'3', INVERT|'4', INVERT|'5', INVERT|'6', INVERT|'7', INVERT|'8', INVERT|'9', INVERT|'a', INVERT|'b', INVERT|'c', INVERT|'d', INVERT|'e', INVERT|'f',

 INVERT|'0', INVERT|'1', INVERT|'2', INVERT|'3', INVERT|'4', INVERT|'5', INVERT|'6', INVERT|'7', INVERT|'8', INVERT|'9', INVERT|'A', INVERT|'B', INVERT|'C', INVERT|'D', INVERT|'E', INVERT|'F',
 INVERT|'0', INVERT|'1', INVERT|'2', INVERT|'3', INVERT|'4', INVERT|'5', INVERT|'6', INVERT|'7', INVERT|'8', INVERT|'9', INVERT|'a', INVERT|'b', INVERT|'c', INVERT|'d', INVERT|'e', INVERT|'f',
};


 #ifndef SIDMAKER
  static const unsigned char ScopeCombinedChars [(1+TUI_SCOPE_SUBPOSITION_Y_RANGE+1)*TUI_SCOPE_SUBPOSITION_Y_RANGE] = { // [SUBPOSITION_Y_RANGE] = { //ScopeNewChar (right/new character) value lookup for ScopeOldChar values (left/old character)
    /*{*/ ','/*'_'*/, ',', '.', '-', '~', '\"', '\'', '`' /*}*/, //for ScopeOldChar==SCOPE_EMPTY_CHAR: ' ' - no combining
    /*{*/ ','/*'_'*/, ','/*'_'*/, ',', ';', ';',  '/',  '/', '/' /*}*/, //for ScopeOldChar==0 ( '_' )
    /*{*/ ','/*'_'*/, ',', ';', ';', '~',  '/',  '/', '/' /*}*/, //for ScopeOldChar==1 ( ',' ) //the thinner line-based, looks better, resembles more like a scope-signal
    /*{*/ ',', ',', '.', '~', '~',  '/',  '/', '/' /*}*/, //for ScopeOldChar==2 ( '.' )
    /*{*/ ';', ';', '~', '-', '~',  '~', '\"','\"' /*}*/, //for ScopeOldChar==3 ( '-' )
    /*{*/ ';', ';', '~', '~', '~',  '~', '\"','\"' /*}*/, //for ScopeOldChar==4 ( '~' )
    /*{*/'\\','\\','\\', '~', '~', '\"', '\"','\"' /*}*/, //for ScopeOldChar==5 ( '"' )
    /*{*/'\\','\\','\\', '~', '~', '\"', '\"','\"' /*}*/, //for ScopeOldChar==6 ( ''' )
    /*{*/'\\','\\','\\','\\', '~', '\"', '\"','\'' /*}*/, //for ScopeOldChar==7 ( '`' )
 // /*{*/ '_', '_', ',', ';', 'r',  '/',  '/', '/' /*}*/, //for ScopeOldChar==0 ( '_' )  //a fatter one with letters, doesn't look as good as the line-based
 // /*{*/ '_', ',', ';', 'r', 'x',  '/',  '/', '/' /*}*/, //for ScopeOldChar==1 ( ',' )
 // /*{*/ ',', ',', ';', 'r', 'x',  '/',  '/', '/' /*}*/, //for ScopeOldChar==2 ( '.' )
 // /*{*/ ';', ';', 'x', '~', '~',  '*', '\"','\"' /*}*/, //for ScopeOldChar==3 ( '-' )
 // /*{*/ 't', 'x', '?', '=', '#',  '*',  '^','\"' /*}*/, //for ScopeOldChar==4 ( '~' )
 // /*{*/'\\','\\','\\', 't', '#',  '*',  '*','\"' /*}*/, //for ScopeOldChar==5 ( '"' )
 // /*{*/'\\','\\','\\', 't', '*', '\"', '\"', '"' /*}*/, //for ScopeOldChar==6 ( ''' )
 // /*{*/'\\','\\','\\','\\', 't', '\"', '\"','\'' /*}*/, //for ScopeOldChar==7 ( '`' )
    /*{*/ ' ', '|', ' ', ' ', ' ', ' ',  ' ',  ' ' /*}*/  //empty character where's no wave
  };
 #endif //SIDMAKER


 enum { INFOSPRITE_NUMBER = 5, HEXNUMBER_AMOUNT = 16, INFO_HEXNUMBER_HEIGHT = 5,
  INFO_OCTAVE_OFFSET = 3, INFO_OCTAVE_NYBBLE = 1, INFO_PLAYTIME_OFFSET = 4, INFO_RASTERTIME_OFFSET = (7*SPRITE_BYTEWIDTH),
  INFO_CURSORADVANCE_OFFSET = INFO_RASTERTIME_OFFSET+2, INFO_CURSORADVANCE_NYBBLE=0,
  INFO_SPRITECHAR_HASH_XOR_CONSTANT = 0x10, //0x1EA /*490*/, //INFO_SPRITECHAR_HASH_MODULO = 0x17 /*23*/,
  //hasher.c found  modulo '33' (0x21) with constant XOR-value '74' (0x4A) for the full 0..F range   (or constant 1707 with modulo 29)
  //but for range 0..D it also found constant XOR-value '16' (0x10) (without need to mask) to avoid slow modulo
 };

/*static const char SpriteHexChars [HEXNUMBER_AMOUNT] [INFO_HEXNUMBER_HEIGHT] = { //they're inverse characters in C64 upper-border sprites
       //   hasher checksums: (^=0x1EA and %=0x17 in every round) or (^=0x10 in every round for values 0..D)
  { 0x1,0x5,0x5,0x5,0x1 }, //0  4                                     33
  { 0xB,0x3,0xB,0xB,0x1 }, //1  0                                     21
  { 0x1,0xD,0x9,0x7,0x1 }, //2  3                                     15
  { 0x1,0xD,0x9,0xD,0x3 }, //3  11                                    23
  { 0xB,0x7,0x1,0xD,0xD }, //4  1                                     61
  { 0x1,0x7,0x1,0xD,0x3 }, //5  16                                    41
  { 0x9,0x7,0x3,0x5,0x3 }, //6  6                                     43
  { 0x1,0xD,0xB,0xB,0xB }, //7  21                                    31
  { 0x1,0x5,0x1,0x5,0x1 }, //8  5                                     29
  { 0x1,0x5,0x1,0xD,0x3 }, //9  22                                    39
  { 0x1,0x5,0x1,0x5,0x5 }, //A  9                                     1
  { 0x3,0x5,0x3,0x5,0x3 }, //B  10                                    35
  { 0x9,0x7,0x7,0x7,0x9 }, //C  18                                    87
  { 0x3,0x5,0x5,0x5,0x3 }, //D  15                                    37
  { 0x9,0x7,0x3,0x7,0x1 }, //E  2                                     43 - same sum as for 6
  { 0x1,0x7,0x3,0x7,0x7 }  //F  20                                    41 - same sum as for 5
 };*/
 static const char SpriteHexCharSumToHex [] = {
// 0   1   2   3   4   5   6   7    8   9   10  11  12  13  14  15   (^=0x10 in every round for values 0..D)
  0x0,0xA,0x0,0x0,0x0,0x0,0x0,0x0, 0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x2,
//16  17   18  19 20  21   22  23   24  25  26  27  28  29  30  31
  0x0,0x0,0x0,0x0,0x0,0x1,0x0,0x3, 0x0,0x0,0x0,0x0,0x0,0x8,0x0,0x7,      //   0   1        2   3   4            0   1   2        3   4
//32  33   34  35  36  37  38  39   40 41:5  42 43:6  44  45  46  47     //5:0x1,0x7,diff:0x1,0xD,0x3     //6: 0x9,0x7,0x3,diff:0x5,0x3
  0x0,0x0,0x0,0xB,0x0,0xD,0x0,0x9, 0x0,0xF ,0x0,0xE, 0x0,0x0,0x0,0x0,    //F:0x1,0x7,diff:0x3,0x7,0x7     //E: 0x9,0x7,0x3,diff:0x7,0x1
//48  49   50  51  52  53  54  55   56  57  58  59  60  61  62  63       //F=5+A: if (byte3 & 2) it's F   //E=6+8: add ( (byte3 & 2) <<2 )
  0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0, 0x0,0x0,0x0,0x0,0x0,0x4,0x0,0x0,      //(byte2 & 2) is 0               //(byte2 & 2) is 1
//64  65   66  67  68  69  70  71   72  73  74  75  76  77  78  79       //common solution for 5,6:  +=  ((byte3 & 2) << 2) + (~byte2 & 2)
  0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0, 0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0,      //       or       for E,F:  -=  ((~byte3 & 2) << 2) + (~byte2 & 2)
//80  81   82  83  84  85  86  87   88  89  90  91  92  93  94  95
  0x0,0x0,0x0,0x0,0x0,0xC,0x0,0xC
 };

 static const word TrackSpriteAddresses [SID_CHANNEL_AMOUNT] = { //not present for 1SID, just for 2SID..4SID
  TOPSPRITE_ADDRESS + 0*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 1,
  TOPSPRITE_ADDRESS + 2*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 0,
  TOPSPRITE_ADDRESS + 3*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 2,
 };

 static const word PatternSpriteAddresses [SID_CHANNEL_AMOUNT] = {
  TOPSPRITE_ADDRESS + 0*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 1,
  TOPSPRITE_ADDRESS + 2*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 0,
  TOPSPRITE_ADDRESS + 3*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 2
 };
 static const word PatternSpriteAddresses2SID [SID_CHANNEL_AMOUNT] = {
  TOPSPRITE_ADDRESS + 0*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 2,
  TOPSPRITE_ADDRESS + 2*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 1,
  TOPSPRITE_ADDRESS + 4*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 0
 };

 static const word PatternSizeSpriteAddresses [SID_CHANNEL_AMOUNT] = { //left-nybble is a low nybble
  TOPSPRITE_ADDRESS + 1*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 0,
  TOPSPRITE_ADDRESS + 2*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 2,
  TOPSPRITE_ADDRESS + 4*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 1
 };
 static const word PatternSizeSpriteAddresses2 [SID_CHANNEL_AMOUNT] = { //left-nybble is a low nybble
  TOPSPRITE_ADDRESS + 1*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 1,
  TOPSPRITE_ADDRESS + 3*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 0,
  TOPSPRITE_ADDRESS + 4*SPRITE_MEMALIGN + 15 * SPRITE_BYTEWIDTH + 2
 };


enum {
 ORDERLIST_HEXNUMBER_HEIGHT = INFO_HEXNUMBER_HEIGHT, ORDERLIST_CANNEL_SPRITE_SPACING = 2,
 ORDERLIST_CHANNEL_SPRITE_PADDING = ( (ORDERLIST_HEXNUMBER_HEIGHT + ORDERLIST_CANNEL_SPRITE_SPACING) * SPRITE_BYTEWIDTH ),
 ORDERLIST_LEFT_SPRITECHAR_HASH_XOR_CONSTANT = 0xB, ORDERLIST_RIGHT_SPRITECHAR_HASH_XOR_CONSTANT = 0x16,
 CHARCODE__ORDERLIST_PLAYPOSITION = ' '
};

//Orderlist sprite-number hashes,  //data coming from 'seqchr2' in native C64 source-code: sources/graphics/graphics.inc
/*static const char OrderlistSpriteLeftHexChars [HEXNUMBER_AMOUNT+2] [ORDERLIST_HEXNUMBER_HEIGHT] = {  //hasher.c found: ^=0x29 (41) and %=21 in every sum-round
             //hasher checksums for ^=0x29 %=21  (^=1420 for high-nybble value)  or  ^=0xB (11) for values 0..E
 { 0x7,0x5,0x5,0x5,0x7 }, //0   9                                                18
 { 0x2,0x6,0x2,0x2,0x7 }, //1  13                                                0
 { 0x7,0x1,0x3,0x4,0x7 }, //2  16                                                31
 { 0x7,0x1,0x3,0x1,0x6 }, //3   5                                                5
 { 0x2,0x4,0x7,0x1,0x1 }, //4  14                                                6
 { 0x7,0x4,0x7,0x1,0x6 }, //5  19                                                44
 { 0x3,0x4,0x6,0x5,0x6 }, //6  18                                                13
 { 0x7,0x1,0x2,0x2,0x2 }, //7   3                                                27
 { 0x7,0x5,0x7,0x5,0x7 }, //8   4                                                32
 { 0x7,0x5,0x7,0x1,0x6 }, //9  20                                                45
 { 0x7,0x5,0x7,0x5,0x5 }, //A   2                                                34
 { 0x6,0x5,0x6,0x5,0x6 }, //B  15                                                19
 { 0x3,0x4,0x4,0x4,0x3 }, //C  17                                                25
 { 0x6,0x5,0x5,0x5,0x6 }, //D   7                                                28
 { 0x7,0x4,0x6,0x4,0x7 }, //E   6                                                39               byte  0   1   2   3   4
 { 0x7,0x4,0x6,0x4,0x4 }, //F   0                                                34 //same as for 0xA: 0x7,0x5,0x7,0x5,0x5
 { 0x0,0x0,0x2,0x0,0x0 }, //.                                                    9             vs 0xF: 0x7,0x4,0x6,0x4,0x4, solution: 0xA += (byte3 & 1) * 5
 { 0x0,0x0,0xF,0x0,0x0 }  //-                                                    4
 { 0x0,0x0,0x0,0x0,0x0 }, //' '                                                  11 //empty (blinking orderlist-number)
};*/
 static const unsigned char OrderlistSpriteLeftCharSumToNybble [] = {
// 0    1   2    3    4           5   6   7     8    9           10   11                                      12    13  14  15   (^=0xB in every round for values 0..E)
  0x1,0xFF,0xFF,0xFF,0x11/*'-'*/,0x3,0x4,0xFF, 0xFF,0x10/*'.'*/,0xFF,0x12/*CHARCODE__ORDERLIST_PLAYPOSITION*/,0xFF,0x6,0xFF,0xFF,
//16    17   18 19   20   21   22   23   24   25   26  27  28   29  30   31
  0xFF,0xFF,0x0,0xB,0xFF,0xFF,0xFF,0xFF, 0xFF,0xC,0xFF,0x7,0xD,0xFF,0xFF,0x2,
//32   33  34  35    36   37  38   39    40   41   42  43   44  45  46  47
  0x8,0xFF,0xF,0xFF,0xFF,0xFF,0xFF,0xE, 0xFF,0xFF,0xFF,0xFF,0x5,0x9
 };

 static const char TUIorderlistSpriteLeftCharNybbleToChar [] = {
  '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F','.','-', CHARCODE__ORDERLIST_PLAYPOSITION
 };
 static const char GUIorderlistSpriteLeftCharNybbleToChar [] = {
  0xE8,0xE9,0xEA,0xEB,0xEC,0xED,0xEE,0xEF, 0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7, 0xE7, 0xF8, CHARCODE__ORDERLIST_PLAYPOSITION /*0xF9*/
 };
 /*static const char TUIorderlistSpriteLeftCharSumToChar [] = {
// 0   1   2   3   4   5   6   7    8   9   10  11                              12  13  14  15   (^=0xB in every round for values 0..E)
  '1',' ',' ',' ','-','3','4',' ', ' ','.',' ',CHARCODE__ORDERLIST_PLAYPOSITION,' ','6',' ',' ',
//16  17  18   19  20  21  22  23   24  25  26  27  28  29  30  31
  ' ',' ','0','B',' ',' ',' ',' ', ' ','C',' ','7','D',' ',' ','2',
//32  33   34  35  36  37  38  39   40 41   42  43  44  45  46  47
  '8',' ','F',' ',' ',' ',' ','E', ' ',' ',' ',' ','5','9'
 };*/

/*static const char OrderlistSpriteRightHexChars [HEXNUMBER_AMOUNT+2] [ORDERLIST_HEXNUMBER_HEIGHT] = { //mostly the same as left-digits but shifted left
        //hasher checksums for ^=1157 %=27  or  ^=0x16 (22) for values 0..D    (if shifted right,  ^=0xB (11) for 0..D or ^=1506 %=29 for 0..F
 { 0xE,0xA,0xA,0xA,0xE }, //0  22                 36                             18
 { 0x4,0xC,0x4,0x4,0xE }, //1  13                 0                              0
 { 0xE,0x2,0x6,0xC,0xE }, //2  17                 2                              1
 { 0xE,0x2,0x6,0x2,0xE }, //3   7                 8                              4
 { 0x2,0x4,0xE,0x2,0x2 }, //4  26                 10                             5
 { 0xE,0x8,0xE,0x2,0xE }, //5   8                 70                             35
 { 0xE,0x8,0xE,0xA,0xE }, //6  16                 78                             39
 { 0xE,0x2,0x2,0x2,0x2 }, //7  18                 24                             12
 { 0xE,0xA,0xE,0xA,0xE }, //8   2                 64                             32
 { 0xE,0xA,0xE,0x2,0xE }, //9   0                 88                             44
 { 0xE,0xA,0xE,0xA,0xA }, //A   6                 68                             34
 { 0xC,0xA,0xC,0xA,0xC }, //B   1                 38                             19
 { 0x6,0x8,0x8,0x8,0x6 }, //C  11                 50                             25                0   1   2   3   4
 { 0xC,0xA,0xA,0xA,0xC }, //D  10                 56                             28          0x6: 0xE,0x8,0xE,0xA,0xE
 { 0xE,0x8,0xC,0x8,0xE }, //E  20                 78 //same as for 6             39          0xE: 0xE,0x8,0xC,0x8,0xE
 { 0xE,0x8,0xC,0x8,0x8 }, //F  14                 68 //same as for 0xA           34          solution: -= (byte3 & 2) << 2
 { 0x0,0x0,0x4,0x0,0x0 }, //.                     18
 { 0x0,0x0,0xF,0x0,0x0 }  //-                     25
 { 0x0,0x0,0x0,0x0,0x0 }, //' '                   22     //empty (blinking orderlist-number)
};*/
 static const char OrderlistSpriteRightCharSumToNybble [] = {
// 0   1    2   3    4    5    6    7     8   9   10   11   12   13   14   15   (^=0x16 in every round for values 0..D)
  0x1,0xFF,0x2,0xFF,0xFF,0xFF,0xFF,0xFF, 0x3,0xFF,0x4,0xFF,0xFF,0xFF,0xFF,0xFF,
// 16   17   18          19   20   21   22                                       23   24  25           26   27   28   29  30    31
  0xFF,0xFF,0x10/*'.'*/,0xFF,0xFF,0xFF,0x12/*CHARCODE__ORDERLIST_PLAYPOSITION*/,0xFF, 0x7,0x11/*'-'*/,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
// 32   33   34   35  36   37  38   39   40    41   42   43   44   45   46   47
  0xFF,0xFF,0xFF,0xFF,0x0,0xFF,0xB,0xFF, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
// 48   49  50   51   52   53   54   55   56   57   58   59   60   61   62   63
  0xFF,0xFF,0xC,0xFF,0xFF,0xFF,0xFF,0xFF, 0xD,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,
//64   65   66   67  68   69  70   71    72   73   74   75   76   77  78   79
  0x8,0xFF,0xFF,0xFF,0xF,0xFF,0x5,0xFF, 0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xE,0xFF,
// 80   81   82   83   84   85   86   87   88  89  90  91  92  93  94  95
  0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF, 0x9
 };

 static const char TUIorderlistSpriteRightCharNybbleToChar [] = {
  '0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F','.','-', CHARCODE__ORDERLIST_PLAYPOSITION
 };
 static const char GUIorderlistSpriteRightCharNybbleToChar [] = {
  0x66,0x67,0x68,0x69,0x6A,0x6B,0x6C,0x6F, 0x71,0x72,0x73,0x74,0x76,0x77,0x78,0x79, 0x65, 0x61, CHARCODE__ORDERLIST_PLAYPOSITION /*0x62*/
 };
/* static const char TUIorderlistSpriteRightCharSumToChar [] = {
// 0   1   2   3   4   5   6   7    8   9   10  11  12  13  14  15   (^=0x16 in every round for values 0..D)
  '1',' ','2',' ',' ',' ',' ',' ', '3',' ','4',' ',' ',' ',' ',' ',
//16  17   18  19  20  21  22                              23   24  25  26  27  28  29  30  31
  ' ',' ','.',' ',' ',' ',CHARCODE__ORDERLIST_PLAYPOSITION,' ', '7','-',' ',' ',' ',' ',' ',' ',
//32  33   34  35  36  37  38  39   40 41   42  43  44  45  46  47
  ' ',' ',' ',' ','0',' ','B',' ', ' ',' ',' ',' ',' ',' ',' ',' ',
//48  49   50  51  52  53  54  55   56  57  58  59  60  61  62  63
  ' ',' ','C',' ',' ',' ',' ',' ', 'D',' ',' ',' ',' ',' ',' ',' ',
//64  65   66  67  68  69  70  71   72  73  74  75  76  77  78  79
  '8',' ',' ',' ','F',' ','5',' ', ' ',' ',' ',' ',' ',' ','E',' ',
//80  81   82  83  84  85  86  87   88  89  90  91  92  93  94  95
  ' ',' ',' ',' ',' ',' ',' ',' ', '9'
 };*/

 static word OrderlistNumberSpriteAddresses [TUI_ORDERLIST_HEIGHT]; //BOTTOMSPRITE_ADDRESS + (i / SPRITE_BYTEWIDTH) * SPRITE_MEMALIGN + (i % SPRITE_BYTEWIDTH);

 static unsigned char OrderlistDisplayedData [SID_CHANNEL_AMOUNT] [C64_ORDERLIST_WIDTH /*TUI_ORDERLIST_HEIGHT * 2*/];

#endif //end of ENABLED_TUI



