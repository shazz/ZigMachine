// The OSD font ROM's rotated A-Z (tools/glass_export.zig, the menu's section strip), added to a
// testbench's copy of the machine's font so its model matches the generated ROM: glyph
// OSD_ROT_BASE + k is 'A' + k turned 90 degrees counter-clockwise, its top on the left, read
// bottom to top. Written here independently of the exporter, so a pixel check catches a
// rotation the wrong way, a wrong base, or the letters missing. Returns false if a slot the
// rotated letters take is not blank in the font (the exporter refuses such a font too).
#pragma once

static bool add_rotated_letters(unsigned char* font_raw) {
    bool blank = true;
    for (unsigned k = 0; k < 26; k++) {
        unsigned char* dst = &font_raw[(OSD_ROT_BASE + k) * 64];
        for (int i = 0; i < 64; i++) blank = blank && dst[i] == 0;
        for (int r = 0; r < 8; r++)
            for (int c = 0; c < 8; c++) dst[r * 8 + c] = font_raw[('A' + k) * 64 + c * 8 + (7 - r)];
    }
    return blank;
}
