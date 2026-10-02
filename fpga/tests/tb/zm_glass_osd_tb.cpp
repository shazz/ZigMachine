// CXXRTL testbench for rtl/glass/zm_glass_osd.v: whole VESA 800x600 frames
// through the overlay, every output pixel checked against a model built from
// the machine's font file itself (argv[1], machine/assets/fonts/...raw), not
// from the generated ROM, so the exporter is checked too.
//
// Frame 0: OSD off, the stream must pass through untouched (3 clocks late).
// Frame 1+: OSD on, text with inverse cells; every pixel must be the model's.
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <vector>

#include "zm_glass_osd.cc"

using Top = cxxrtl_design::p_zm__glass__osd;
static int failures = 0;
#define CHECK(cond, ...)                                     \
    do {                                                     \
        if (!(cond)) {                                       \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__); \
            std::printf(__VA_ARGS__);                        \
            std::printf("\n");                               \
            if (++failures > 10) std::exit(1);               \
        }                                                    \
    } while (0)

static const int H_TOTAL = 1056, V_TOTAL = 628, H_SYNC0 = 840, H_SYNC1 = 968, V_SYNC0 = 601, V_SYNC1 = 605;
static const unsigned FG = 0xE0C020, BG = 0x102040;
static Top top;
static unsigned char font_raw[256 * 64];
static unsigned text[OSD_CHARS];

struct In { unsigned rgb; bool de, hs, vs; int x, y; };

static void tick() {
    top.p_clk.set(false);
    top.p_wclk.set(false);
    top.step();
    top.p_clk.set(true);
    top.p_wclk.set(true);
    top.step();
}

static void write_text() {
    for (unsigned i = 0; i < OSD_CHARS; i++) {
        unsigned c = (i * 7 + 33) & 0xFF;
        if (i / OSD_COLS == 3) c |= OSD_INVERSE;   // a whole inverse row: the menu's cursor
        if (i % 5 == 0) c = ' ';
        text[i] = c;
        top.p_we.set(true);
        top.p_waddr.set(i);
        top.p_wdata.set(c);
        tick();
    }
    top.p_we.set(false);
}

static unsigned model(const In& in, bool osd) {
    int ox = in.x - int(OSD_X0), oy = in.y - int(OSD_Y0);
    if (!osd || !in.de || ox < 0 || oy < 0 || ox >= int(OSD_WIDTH) || oy >= int(OSD_HEIGHT)) return in.rgb;
    unsigned c = text[(oy / 16) * OSD_COLS + ox / 16];
    bool ink = font_raw[(c & 0xFF) * 64 + ((oy / 2) % 8) * 8 + (ox / 2) % 8] == 1;
    if (c & OSD_INVERSE) ink = !ink;
    return ink ? FG : BG;
}

// One frame; outputs are compared with the input three clocks earlier.
static void frame(bool osd, std::deque<In>& pipe) {
    for (int y = 0; y < V_TOTAL; y++)
        for (int x = 0; x < H_TOTAL; x++) {
            In in{(unsigned(x * 3) & 0xFF) << 16 | (unsigned(y) & 0xFF) << 8 | 0x5A, x < 800 && y < 600,
                  x >= H_SYNC0 && x < H_SYNC1, y >= V_SYNC0 && y < V_SYNC1, x, y};
            top.p_r.set(in.rgb >> 16);
            top.p_g.set((in.rgb >> 8) & 0xFF);
            top.p_b.set(in.rgb & 0xFF);
            top.p_de.set(in.de);
            top.p_hsync.set(in.hs);
            top.p_vsync.set(in.vs);
            tick();
            pipe.push_back(in);
            if (pipe.size() < 3) continue;
            const In& old = pipe.front();
            unsigned got = top.p_r__o.get<unsigned>() << 16 | top.p_g__o.get<unsigned>() << 8 | top.p_b__o.get<unsigned>();
            CHECK(top.p_de__o.get<bool>() == old.de && top.p_hs__o.get<bool>() == old.hs &&
                      top.p_vs__o.get<bool>() == old.vs, "syncs not 3 clocks late at (%d,%d)", old.x, old.y);
            unsigned want = model(old, osd);
            CHECK(got == want, "osd %d at (%d,%d): got %06x want %06x", osd, old.x, old.y, got, want);
            pipe.pop_front();
        }
}

int main(int argc, char** argv) {
    FILE* f = argc > 1 ? std::fopen(argv[1], "rb") : nullptr;
    if (!f || std::fread(font_raw, 1, sizeof font_raw, f) != sizeof font_raw) {
        std::printf("FAIL: need the font file as argv[1]\n");
        return 1;
    }
    std::fclose(f);
    top.p_fg.set(FG);
    top.p_bg.set(BG);
    top.p_rst.set(true);
    tick();
    top.p_rst.set(false);
    write_text();
    std::deque<In> pipe;
    // Start a little before VSYNC so the overlay has seen one and knows where y=0 is.
    for (int i = 0; i < 3; i++) tick();
    top.p_en.set(false);
    frame(false, pipe);
    top.p_en.set(true);
    frame(true, pipe);
    text[0] = 'A' | OSD_INVERSE;           // a rewrite between frames shows on the next one
    top.p_we.set(true);
    top.p_waddr.set(0);
    top.p_wdata.set(text[0]);
    tick();
    top.p_we.set(false);
    pipe.clear();
    frame(true, pipe);
    if (failures) return 1;
    std::printf("zm_glass_osd: ok\n");
    return 0;
}
