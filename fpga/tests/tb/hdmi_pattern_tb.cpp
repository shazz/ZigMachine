// CXXRTL testbench for rtl/board/hdmi_pattern.v (with rtl/video/zm_vtiming.v):
// captures whole frames from the pattern's registered de/rgb and checks the
// white frame on the exact edges, the black ring inside it, the bars, every ramp
// level 3 pixels wide, and the box: 48x48, moved by (4, 2) a frame.
// Built and run by tests/test_rtl.py. `hdmi_pattern_tb DIR [N]` also writes
// frames 0 and N (default 60) as DIR/frame_<n>.ppm (`make -C fpga hdmi-test-sim`).
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include "hdmi_pattern.cc"

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

constexpr int W = 800, H = 600;
using Frame = std::vector<unsigned>;  // 0xRRGGBB, row-major
using Top = cxxrtl_design::p_hdmi__pattern;

static void tick(Top &top) {
    top.p_clk.set(false);
    top.step();
    top.p_clk.set(true);
    top.step();
}

// One whole output frame (1056 x 628 clocks): the de pixels in order.
static Frame capture(Top &top) {
    Frame f;
    f.reserve(W * H);
    for (long i = 0; i < 1056L * 628L; i++) {
        tick(top);
        if (top.p_de.get<bool>())
            f.push_back(top.p_r.get<unsigned>() << 16 | top.p_g.get<unsigned>() << 8 | top.p_b.get<unsigned>());
    }
    return f;
}

static void check_edges(const Frame &f) {
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            const unsigned p = f[y * W + x];
            const bool e0 = x == 0 || x == W - 1 || y == 0 || y == H - 1;
            const bool e1 = !e0 && (x == 1 || x == W - 2 || y == 1 || y == H - 2);
            if (e0) CHECK(p == 0xFFFFFF, "edge (%d, %d) = %06X, want white", x, y, p);
            if (e1) CHECK(p == 0x000000, "ring (%d, %d) = %06X, want black", x, y, p);
        }
}

static void check_bars_and_ramps(const Frame &f) {
    const unsigned bars[7] = {0xBFBFBF, 0xBFBF00, 0x00BFBF, 0x00BF00, 0xBF00BF, 0xBF0000, 0x0000BF};
    const unsigned cast[7] = {0x0000BF, 0, 0xBF00BF, 0, 0x00BFBF, 0, 0xBFBFBF};
    for (int i = 0; i < 7; i++) {
        const int x = 114 * i + 57;
        CHECK(f[150 * W + x] == bars[i], "bar %d = %06X", i, f[150 * W + x]);
        CHECK(f[320 * W + x] == cast[i], "castellation %d = %06X", i, f[320 * W + x]);
    }
    const unsigned shift[4] = {16, 8, 0, 0};
    for (int ramp = 0; ramp < 4; ramp++) {
        const int y = 460 + 35 * ramp + 17;
        for (int x = 2; x < W - 2; x++) {
            const unsigned p = f[y * W + x];
            const unsigned want_level = (x >= 16 && x < 784) ? unsigned(x - 16) / 3 : 0;
            const unsigned want = ramp == 3 ? want_level * 0x010101 : want_level << shift[ramp];
            CHECK(p == want, "ramp %d x %d = %06X, want %06X", ramp, x, p, want);
        }
    }
}

// The box's top-left corner, after checking it is one solid 48x48 square.
static void find_box(const Frame &f, int &bx, int &by) {
    long n = 0;
    bx = by = -1;
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++)
            if (f[y * W + x] == 0xFF8000) {
                if (n++ == 0) bx = x, by = y;
            }
    CHECK(n == 48 * 48, "box has %ld pixels", n);
    CHECK(by >= 340 && by + 48 <= 460, "box at y %d leaves its band", by);
}

static void write_ppm(const std::string &path, const Frame &f) {
    FILE *out = std::fopen(path.c_str(), "wb");
    if (!out) { std::printf("FAIL cannot write %s\n", path.c_str()); std::exit(1); }
    std::fprintf(out, "P6\n%d %d\n255\n", W, H);
    for (unsigned p : f) {
        const unsigned char px[3] = {(unsigned char)(p >> 16), (unsigned char)(p >> 8), (unsigned char)p};
        std::fwrite(px, 1, 3, out);
    }
    std::fclose(out);
}

int main(int argc, char **argv) {
    Top top;
    top.p_rst.set(true);
    tick(top);
    tick(top);
    top.p_rst.set(false);
    const int last = argc > 2 ? std::atoi(argv[2]) : 1;
    int px = 0, py = 0;
    for (int n = 0; n <= last; n++) {
        const Frame f = capture(top);
        CHECK(f.size() == size_t(W) * H, "frame %d: %zu de pixels", n, f.size());
        if (f.size() != size_t(W) * H) break;
        if (n != 0 && n != 1 && n != last) continue;
        check_edges(f);
        check_bars_and_ramps(f);
        int bx, by;
        find_box(f, bx, by);
        if (n == 1) CHECK(bx == px + 4 && by == py + 2, "box (%d, %d) -> (%d, %d), want +4, +2", px, py, bx, by);
        px = bx, py = by;
        if (argc > 1 && (n == 0 || n == last)) write_ppm(std::string(argv[1]) + "/frame_" + std::to_string(n) + ".ppm", f);
    }
    std::printf(failures ? "hdmi_pattern: %d failure(s)\n" : "hdmi_pattern: frames OK\n", failures);
    return failures ? 1 : 0;
}
