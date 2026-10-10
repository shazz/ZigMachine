// CXXRTL testbench for the OSD test bitstream (rtl/board/osd_test_core.v: the
// HDMI pattern, the glass OSD over it, the glass registers as the GP0 slave).
// It plays fpga/tools/osd_uboot_demo.sh's steps over the AXI port and checks
// every pixel of a whole frame after each one against a model: the pattern
// passed through (3 clocks late) outside the OSD or with it off, else the
// font's ink or paper for the text the model expects. The model reads the
// machine's font file (argv[1]) and spells the banner out itself, so
// osd_banner.v's strings and gen/glass_font.vh are both checked.
// `osd_test_tb FONT DIR` also writes each step's frame as DIR/osd_<n>_<step>.ppm.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <string>
#include <vector>

#include "osd_test_core.cc"

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

static const int W = 800, H = 600, FRAME = 1056 * 628;
static cxxrtl_design::p_osd__test__core top;
static unsigned char font_raw[256 * 64];
static unsigned text[OSD_CHARS], fg = 0xFFFFFF, bg = 0x000000;
static bool en = true, checking = false;
static std::vector<unsigned> shot(W * H);

struct In { unsigned rgb; bool de, hs, vs; int x, y; };
static std::deque<In> pipe;
static int cx = 0, cy = 0;
static bool pde = false, pvs = false, rose = false;  // rose: VSYNC rose on the last clock

static unsigned model(const In& in) {
    int ox = in.x - int(OSD_X0), oy = in.y - int(OSD_Y0);
    if (!en || !in.de || ox < 0 || oy < 0 || ox >= int(OSD_WIDTH) || oy >= int(OSD_HEIGHT)) return in.rgb;
    unsigned c = text[(oy / 16) * OSD_COLS + ox / 16];
    bool ink = font_raw[(c & 0xFF) * 64 + ((oy / 2) % 8) * 8 + (ox / 2) % 8] == 1;
    return (ink != bool(c & OSD_INVERSE)) ? fg : bg;
}

// One clock. The pattern's registered output after clock t reaches the
// picture after clock t + 3 (the OSD's three stages).
static void tick() {
    top.p_clk.set(false);
    top.step();
    top.p_clk.set(true);
    top.step();
    top.step();
    In in{top.p_pat__r.get<unsigned>() << 16 | top.p_pat__g.get<unsigned>() << 8 | top.p_pat__b.get<unsigned>(),
          top.p_pat__de.get<bool>(), top.p_pat__hs.get<bool>(), top.p_pat__vs.get<bool>(), cx, cy};
    rose = in.vs && !pvs;
    if (rose) cx = cy = 0;
    else if (in.de) cx++;
    else if (pde) cx = 0, cy++;
    pde = in.de, pvs = in.vs;
    pipe.push_back(in);
    if (pipe.size() < 4) return;
    const In old = pipe.front();
    pipe.pop_front();
    if (!checking) return;
    unsigned got = top.p_r.get<unsigned>() << 16 | top.p_g.get<unsigned>() << 8 | top.p_b.get<unsigned>();
    CHECK(top.p_de.get<bool>() == old.de && top.p_hsync.get<bool>() == old.hs && top.p_vsync.get<bool>() == old.vs,
          "syncs not 3 clocks late at (%d,%d)", old.x, old.y);
    CHECK(got == model(old), "at (%d,%d): got %06x want %06x", old.x, old.y, got, model(old));
    if (old.de && old.x < W && old.y < H) shot[old.y * W + old.x] = got;
}

// From the next VSYNC, one whole frame checked; written as a PPM if `ppm` is set.
static void frame(const std::string& ppm) {
    do tick(); while (!rose);
    checking = true;
    for (int i = 0; i < FRAME; i++) tick();
    checking = false;
    if (ppm.empty()) return;
    FILE* f = std::fopen(ppm.c_str(), "wb");
    std::fprintf(f, "P6\n%d %d\n255\n", W, H);
    for (unsigned p : shot) std::fputc(p >> 16, f), std::fputc((p >> 8) & 0xFF, f), std::fputc(p & 0xFF, f);
    std::fclose(f);
}

static void axi_write(unsigned addr, unsigned data) {
    top.p_s__awvalid.set(true), top.p_s__awaddr.set(addr & 0xFFFF), top.p_s__awid.set(5u);
    top.p_s__wvalid.set(true), top.p_s__wdata.set(data), top.p_s__wstrb.set(0xFu);
    bool aw = false, w = false;
    for (int guard = 0; !(aw && w); guard++) {
        CHECK(guard < 10, "write 0x%x never accepted", addr);
        if (guard >= 10) return;
        aw |= top.p_s__awready.get<bool>(), w |= top.p_s__wready.get<bool>();
        tick();
        top.p_s__awvalid.set(!aw), top.p_s__wvalid.set(!w);
    }
    top.p_s__bready.set(true);
    for (int guard = 0; !top.p_s__bvalid.get<bool>(); guard++) {
        CHECK(guard < 5, "no B for 0x%x", addr);
        if (guard >= 5) return;
        tick();
    }
    CHECK(top.p_s__bresp.get<unsigned>() == 0 && top.p_s__bid.get<unsigned>() == 5, "B wrong for 0x%x", addr);
    tick();
    top.p_s__bready.set(false);
}

static unsigned axi_read(unsigned addr) {
    top.p_s__arvalid.set(true), top.p_s__araddr.set(addr & 0xFFFF), top.p_s__arid.set(9u);
    CHECK(top.p_s__arready.get<bool>(), "AR not ready for 0x%x", addr);
    tick();
    top.p_s__arvalid.set(false);
    CHECK(top.p_s__rvalid.get<bool>() && top.p_s__rid.get<unsigned>() == 9 && top.p_s__rlast.get<bool>(),
          "no R for 0x%x", addr);
    unsigned v = top.p_s__rdata.get<unsigned>();
    top.p_s__rready.set(true);
    tick();
    top.p_s__rready.set(false);
    return v;
}

// What osd_banner.v must have written, spelled out again here.
static void banner() {
    const char* rows[16] = {"      ZIGMACHINE OSD TEST", "", " THE PL WROTE THIS AT POWER-ON",
                            " THE FONT, CHARACTERS 00-FF:", "", "", "", "", "", "", "", "", "",
                            " GP0 43C00000  ID 5A4D474C", " WAITING FOR THE ARM (U-BOOT)",
                            "  MICROPHASE Z7-LITE  XC7Z010"};
    for (unsigned i = 0; i < OSD_CHARS; i++) {
        unsigned row = i / OSD_COLS, col = i % OSD_COLS;
        text[i] = col < std::strlen(rows[row]) ? (unsigned char)rows[row][col] : ' ';
        if (row >= 4 && row < 12) text[i] = (row - 4) * OSD_COLS + col;
        if (row == 0 || row == 15) text[i] |= OSD_INVERSE;
    }
}

// The demo script's text write: the row cleared to spaces, then the message.
static void write_row(unsigned row, const char* s) {
    for (unsigned c = 0; c < OSD_COLS; c++) {
        unsigned ch = c < std::strlen(s) ? (unsigned char)s[c] : ' ';
        axi_write(GP0_BASE + OFF_OSD_TEXT + 4 * (row * OSD_COLS + c), ch);
        text[row * OSD_COLS + c] = ch;
    }
}

int main(int argc, char** argv) {
    FILE* f = argc > 1 ? std::fopen(argv[1], "rb") : nullptr;
    if (!f || std::fread(font_raw, 1, sizeof font_raw, f) != sizeof font_raw) {
        std::printf("FAIL: need the font file as argv[1]\n");
        return 1;
    }
    std::fclose(f);
    std::string dir = argc > 2 ? std::string(argv[2]) + "/osd_" : "";
    auto shot_path = [&](const char* step) { return dir.empty() ? dir : dir + step + ".ppm"; };
    top.p_rst.set(true);
    for (int i = 0; i < 4; i++) tick();
    top.p_rst.set(false);
    int n = 0;
    for (tick(); top.p_banner__busy.get<bool>(); tick()) n++;
    CHECK(n <= OSD_CHARS + 2, "the banner took %d clocks", n);
    banner();
    frame(shot_path("1_poweron"));                                      // step 0: power-on
    CHECK(axi_read(GP0_BASE + REG_ID) == ID_VALUE, "ID");               // step 1
    CHECK(axi_read(GP0_BASE + REG_VERSION) == VERSION, "VERSION");
    CHECK(axi_read(GP0_BASE + REG_CTRL) == CTRL_OSD, "CTRL at power-on");
    axi_write(GP0_BASE + REG_SCRATCH, 0x12345678u);
    CHECK(axi_read(GP0_BASE + REG_SCRATCH) == 0x12345678u, "SCRATCH");
    frame("");
    write_row(13, " HELLO FROM THE ARM");                                // step 2
    write_row(14, " TIME 12:34:56");
    frame(shot_path("2_message"));
    axi_write(GP0_BASE + REG_CTRL, 0);                                  // step 3: off
    en = false;
    frame(shot_path("3_off"));
    axi_write(GP0_BASE + REG_CTRL, CTRL_OSD);                           // step 3: on
    en = true;
    frame("");
    axi_write(GP0_BASE + REG_OSD_FG, 0xFFFF00u);                        // step 4: colours
    axi_write(GP0_BASE + REG_OSD_BG, 0x0000AAu);
    fg = 0xFFFF00, bg = 0x0000AA;
    frame(shot_path("4_colours"));
    CHECK(axi_read(GP0_BASE + REG_OSD_FG) == 0xFFFF00u, "OSD_FG read back");
    if (failures) return 1;
    std::printf("osd_test_core: ok\n");
    return 0;
}
