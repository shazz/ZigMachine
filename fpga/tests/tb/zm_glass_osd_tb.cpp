// CXXRTL testbench for rtl/glass/zm_glass_osd.v: whole VESA 800x600 frames
// through the overlay, every output pixel checked against a model built from
// the machine's font file itself (argv[1], machine/assets/fonts/...raw), not
// from the generated ROM, so the exporter is checked too.
//
// Frame 0: OSD off, the stream must pass through untouched (3 clocks late).
// Frame 1+: OSD on, text with inverse cells; every pixel must be the model's.
// Then the F11 overlay: STATS (plain spaces transparent, inverse ones not) and
// the window moved by x0/y0: to the corner, half off the edge, and far enough
// right or down that a beam left of or above it must not wrap into it.
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
// What the quasi-static inputs hold. A frame changes them during VSYNC, so the
// whole next frame sees them settled.
struct Cfg { bool en, stats; int x0, y0; };
static Cfg live{false, false, int(OSD_X0), int(OSD_Y0)};

static void apply(const Cfg& c) {
    top.p_en.set(c.en);
    top.p_stats.set(c.stats);
    top.p_x0.set(unsigned(c.x0));
    top.p_y0.set(unsigned(c.y0));
    live = c;
}

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
        if (i % 5 == 0) c = (i / OSD_COLS == 3) ? (' ' | OSD_INVERSE) : ' ';  // the cursor bar stays solid
        text[i] = c;
        top.p_we.set(true);
        top.p_waddr.set(i);
        top.p_wdata.set(c);
        tick();
    }
    top.p_we.set(false);
}

static unsigned model(const In& in, const Cfg& k) {
    int ox = in.x - k.x0, oy = in.y - k.y0;
    if (!k.en || !in.de || ox < 0 || oy < 0 || ox >= int(OSD_WIDTH) || oy >= int(OSD_HEIGHT)) return in.rgb;
    unsigned c = text[(oy / 16) * OSD_COLS + ox / 16];
    if (k.stats && c == ' ') return in.rgb;
    bool ink = font_raw[(c & 0xFF) * 64 + ((oy / 2) % 8) * 8 + (ox / 2) % 8] == 1;
    if (c & OSD_INVERSE) ink = !ink;
    return ink ? FG : BG;
}

// One frame under `live`, which becomes `next` at VSYNC; outputs are compared
// with the input three clocks earlier.
static void frame(const Cfg& next, std::deque<In>& pipe) {
    const Cfg cur = live;
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
            if (y == V_SYNC0 && x == 0) apply(next);
            tick();
            pipe.push_back(in);
            if (pipe.size() < 3) continue;
            const In& old = pipe.front();
            unsigned got = top.p_r__o.get<unsigned>() << 16 | top.p_g__o.get<unsigned>() << 8 | top.p_b__o.get<unsigned>();
            CHECK(top.p_de__o.get<bool>() == old.de && top.p_hs__o.get<bool>() == old.hs &&
                      top.p_vs__o.get<bool>() == old.vs, "syncs not 3 clocks late at (%d,%d)", old.x, old.y);
            unsigned want = model(old, old.y < V_SYNC0 ? cur : live);
            CHECK(got == want, "osd %d stats %d at %d,%d: (%d,%d): got %06x want %06x", cur.en, cur.stats, cur.x0,
                  cur.y0, old.x, old.y, got, want);
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
    const Cfg centred{true, false, int(OSD_X0), int(OSD_Y0)};
    apply({false, false, int(OSD_X0), int(OSD_Y0)});
    frame(centred, pipe);
    frame(centred, pipe);
    text[0] = 'A' | OSD_INVERSE;           // a rewrite between frames shows on the next one
    top.p_we.set(true);
    top.p_waddr.set(0);
    top.p_wdata.set(text[0]);
    tick();
    top.p_we.set(false);
    pipe.clear();
    const Cfg moves[] = {
        {true, true, int(OSD_X0), int(OSD_Y0)},  // the stats overlay, still centred
        {true, true, 0, 0},                      // in the corner, as F11 puts it
        {true, false, 700, 500},                 // half off the right and bottom edges: clipped
        {true, true, 2000, 100},                 // right of the screen: a beam left of it must not wrap in
        {true, false, 100, 1000},                // below it: likewise for the lines above
        {false, false, int(OSD_X0), int(OSD_Y0)},
    };
    for (const Cfg& next : moves) frame(next, pipe);  // each shows the one before it
    if (failures) return 1;
    std::printf("zm_glass_osd: ok\n");
    return 0;
}
