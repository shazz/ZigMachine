# KESTREL: one built-in font, the Atari ST 8x8 system font in an 8x10 cell (kestrel_font8x10.cpp): 40x20 = 320x200
s/^    {12, 16, font12x16},$/    {8, 10, kestrel_font8x10} \/* KESTREL *\//
/^    {16, 24, font16x24},$/d
/^    {24, 36, font24x36},$/d
/^    {32, 48, font32x48},$/d
/^    {48, 54, font48x54}$/d
s/^  5 \/\/ resolutionCount$/  1 \/\/ resolutionCount (KESTREL)/
s/^#include "font.h"$/extern "C" const uint8_t kestrel_font8x10[]; \/* KESTREL *\//
