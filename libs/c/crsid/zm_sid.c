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
    /* cRSID takes the subtune as a plain char, signed on x86 and unsigned on rv32: past 127 the two
     * would differ, so a subtune is held to 1..127 (HVSC's largest files have fewer). */
    uint32_t sub = subtune ? subtune : h->DefaultSubtune;
    cRSID_initSIDtune(h, (char)(sub > 127 ? 127 : sub));
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

/* zm_sid_raw's tune: a PSID v2 header (big-endian fields, HVSC SID_file_format.txt) and two RTS at
 * $1000. Static: cRSID keeps a pointer to the header while it plays. */
static uint8_t zm_sid_raw_file[0x7C + 2];

uint32_t zm_sid_raw(uint32_t model) {
    uint8_t *f = zm_sid_raw_file;
    memset(f, 0, sizeof zm_sid_raw_file);
    memcpy(f, "PSID", 4);
    f[5] = 2;                    /* version 2 */
    f[7] = 0x7C;                 /* the data's offset */
    f[8] = f[10] = f[12] = 0x10; /* load, init and play at $1000 */
    f[15] = f[17] = 1;           /* one song, the first */
    f[0x77] = 0x04 | (model == 8580 ? 0x20 : 0x10); /* PAL; the SID model */
    f[0x7C] = f[0x7D] = 0x60;                       /* RTS, RTS */
    return zm_sid_load(f, sizeof zm_sid_raw_file, 1);
}

void zm_sid_write(uint32_t reg, uint32_t value) {
    if (zm_sid_loaded && reg <= 0x18) cRSID_C64.IObankWR[0xD400 + reg] = (uint8_t)value;
}
