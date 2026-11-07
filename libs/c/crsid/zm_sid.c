/* The SID engine's door (zm_sid.h): cRSID (Mihaly Horvath "Hermit", libs/c/crsid/README.md) in its
 * light engine at 22.05 kHz mono, PSID only. One translation unit: our config, then cRSID's unity
 * build (libcRSID.c of the PATCHED tree, found on the include path: patch.sh's output), then the
 * door. Built for machine-audio.wasm (build.zig) and natively (fpga/host/crsid.c). */
#include "config/zm_crsid.h"
#ifndef LIBCRSID_HEADER__C64 /* else the includer brought the tree in itself (fpga/host/crsid.c) */
#include "libcRSID.c"
#endif
#include "zm_sid.h"

int zm_crsid_lfsr;
static int zm_sid_loaded;

static int zm_sid_magic(const uint8_t *f, char first) {
    return f[0] == (uint8_t)first && f[1] == 'S' && f[2] == 'I' && f[3] == 'D';
}

uint32_t zm_sid_load(uint8_t *file, uint32_t len, uint32_t subtune) {
    zm_sid_loaded = 0;
    if (len < 0x7C + 2 || len > 0x10000 + 0x7C + 2) return ZM_SID_SHORT;
    if (zm_sid_magic(file, 'R')) return ZM_SID_RSID;
    if (!zm_sid_magic(file, 'P')) return ZM_SID_NOT_SID;
    /* A fresh C64 each time, so a tune never hears what played before it: the globals cleared,
     * the dither LFSR at its seed (patches/audio.c.sed), cRSID's own init. */
    memset(&cRSID_C64, 0, sizeof cRSID_C64);
    memset(&cRSID, 0, sizeof cRSID);
    zm_crsid_lfsr = 0x0055A5AA;
    cRSID_init(ZM_SID_RATE, 0);
    cRSID_SIDheader *h = cRSID_processSIDfileData(file, (int)len);
    if (!h) return ZM_SID_NOT_SID;
    cRSID.HighQualitySID = 0;
    cRSID_initSIDtune(h, (char)(subtune ? subtune : h->DefaultSubtune));
    /* cRSID_generateSound's shadow settings, set once: zm_sid_render calls cRSID_generateSample. */
    cRSID_C64.RealSIDmode = cRSID.RealSIDmode;
    cRSID_C64.AudioThread_SIDchipCount = cRSID_C64.SIDchipCount;
    cRSID_C64.Stereo = CRSID_CHANNELMODE_MONO;
    cRSID_C64.HighQualitySID = 0;
    cRSID_C64.HighQualityResampler = 0;
    zm_sid_loaded = 1;
    return ZM_SID_OK;
}

void zm_sid_render(int16_t *dst, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) dst[i] = zm_sid_loaded ? (int16_t)cRSID_generateSample().L : 0;
}
