/* cRSID, natively (host/audio_sid.c says where and why): its own translation unit, so its macros
 * (LIKELY, INLINE, LFSR...) never meet wasm-rt's. The patched tree is fpga/build/crsid
 * (libs/c/crsid/patch.sh, made by cycles/audio.mk), included by path: no build needs an -I for it. */
#include "../../libs/c/crsid/config/zm_crsid.h"
#include "../build/crsid/libcRSID.c"
#include "../../libs/c/crsid/zm_sid.c"
