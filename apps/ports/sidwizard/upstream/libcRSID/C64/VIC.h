
#include "../libcRSID.h"
#include "../../SIDwizard.h"


#define SCREENWIDTH 40
#define CRAM_ADDRESS    0xD800
#define ROW25_RASTER    0xEE
#define ROW26_RASTER    0xF7
#define C64_MAX_SCANLINES 312
#define VICBANKSEL_ADDRESS 0xDD00


//Helpers for asynchronously displayed graphic data (vs raster-effects)
byte RasterBars [C64_MAX_SCANLINES];
byte SpritEnaBars [C64_MAX_SCANLINES];
byte VICbankBars [C64_MAX_SCANLINES];
byte VCRAMbankBars [C64_MAX_SCANLINES];
byte SpriteColBars [C64_MAX_SCANLINES];
byte SpriteWidthBars [C64_MAX_SCANLINES];
byte Row25colors [SCREENWIDTH];
byte Row26colors [SCREENWIDTH];


