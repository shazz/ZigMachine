// CXXRTL testbench for rtl/board/edid_core.v (via tests/tb/edid_core_top.v): the
// DDC reader against a C++ EEPROM model (tests/tb/ddc_slave.h) holding
// tests/data/edid_hdmi_audio.hex, in five scenarios:
//   plain, a clock-stretching sink, no sink (NAK on 0xA0), a sink stuck mid-byte
//   (bus recovery), and SCL held low (TIMEOUT).
// Every scenario checks the I2C standard-mode timing on the wire and the status;
// the ones that read also capture a whole frame and check the screen: every
// 16x16 cell's character (the `ch` port) against the expected text, and every
// pixel against the machine font (gen/glass_font.vh) drawn 2x. Built and run by
// tests/test_rtl.py.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include "edid_core_top.cc"
#include "ddc_slave.h"

static int failures = 0;
#define CHECK(cond, ...)                                     \
    do {                                                     \
        if (!(cond)) {                                       \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__); \
            std::printf(__VA_ARGS__);                        \
            std::printf("\n");                               \
            if (++failures > 20) std::exit(1);               \
        }                                                    \
    } while (0)

using Top = cxxrtl_design::p_edid__core__top;
static const std::string FPGA = std::string(__FILE__).substr(0, std::string(__FILE__).rfind("/tests/"));
static std::vector<uint8_t> EDID, FONT;

static std::vector<uint8_t> read_hex(const std::string &path) {
    std::ifstream f(path);
    std::vector<uint8_t> out;
    for (std::string line; std::getline(f, line);) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream s(line);
        for (std::string t; s >> t;) out.push_back(uint8_t(std::stoul(t, nullptr, 16)));
    }
    return out;
}

static std::vector<uint8_t> read_font(const std::string &path) {  // "font[N] = 8'hXX;"
    std::ifstream f(path);
    std::vector<uint8_t> out(2048, 0);
    for (std::string line; std::getline(f, line);) {
        unsigned n, v;
        if (std::sscanf(line.c_str(), " font[%u] = 8'h%x;", &n, &v) == 2 && n < 2048) out[n] = uint8_t(v);
    }
    return out;
}

struct Bench {
    std::unique_ptr<Top> top = std::make_unique<Top>();
    DdcSlave slave;
    I2cTiming timing;
    long clocks = 0;

    void tick() {
        const bool scl = !(top->p_scl__low.get<bool>() || slave.scl_low);
        const bool sda = !(top->p_sda__low.get<bool>() || slave.sda_low);
        slave.tick(scl, sda);
        timing.tick(scl, sda);
        top->p_scl__in.set(scl);
        top->p_sda__in.set(sda);
        top->p_clk.set(false);
        top->step();
        top->p_clk.set(true);
        top->step();
        clocks++;
    }
    void reset() {
        slave.begin();
        timing.prev_sda = slave.prev_sda = !slave.sda_low;
        top->p_hpd.set(true);
        top->p_rst.set(true);
        for (int i = 0; i < 4; i++) tick();
        top->p_rst.set(false);
    }
    unsigned status() { return top->p_status.get<unsigned>(); }
};

// The 37 lines of 50 characters the screen should show.
static std::vector<std::string> expected_text(unsigned status, unsigned reads) {
    static const char *words[] = {"WAIT   ", "OK     ", "NAK A0 ", "NAK OFS", "NAK A1 ", "TIMEOUT"};
    std::vector<std::string> t(37, std::string(50, ' '));
    char b[64];
    std::snprintf(b, sizeof b, "EDID  status:%X %s  reads:%02X  hpd:1", status, words[status], reads);
    t[0].replace(0, std::string(b).size(), b);
    for (int ri = 0; ri < 32; ri++) {
        std::string s;
        unsigned sum = 0;
        std::snprintf(b, sizeof b, "%02X: ", ri * 8);
        s = b;
        for (int i = 0; i < 8; i++) {
            const unsigned v = status == 1 ? EDID[ri * 8 + i] : 0;
            std::snprintf(b, sizeof b, " %02X ", v);
            s += b;
            sum += v;
        }
        std::snprintf(b, sizeof b, "=%02X", sum & 0xFF);
        s += b;
        t[ri < 16 ? 2 + ri : 3 + ri].replace(0, s.size(), s);
    }
    const std::string legend = "AA: 8 bytes from address AA  =their sum mod 256";
    t[36].replace(0, legend.size(), legend);
    return t;
}

// One whole frame, from the output's next vsync; then every cell and pixel.
static void check_screen(Bench &b, const char *name) {
    while (!b.top->p_vsync.get<bool>()) b.tick();
    std::vector<uint8_t> ch;
    std::vector<unsigned> px;
    for (long i = 0; i < 1056L * 628L; i++) {
        b.tick();
        if (!b.top->p_de.get<bool>()) continue;
        ch.push_back(b.top->p_ch.get<uint8_t>());
        px.push_back(b.top->p_r.get<unsigned>() << 16 | b.top->p_g.get<unsigned>() << 8 | b.top->p_b.get<unsigned>());
    }
    CHECK(px.size() == 800u * 600u, "%s: %zu pixels in a frame", name, px.size());
    if (px.size() != 800u * 600u) return;
    if (const char *ppm = std::getenv("EDID_PPM")) {  // EDID_PPM=out.ppm: the frame, to look at
        std::ofstream f(ppm, std::ios::binary);
        f << "P6\n800 600\n255\n";
        for (unsigned p : px) f.put(char(p >> 16)).put(char(p >> 8)).put(char(p));
    }
    const auto want = expected_text(b.status(), b.top->p_reads.get<unsigned>());
    int bad_cells = 0, bad_px = 0;
    for (int y = 0; y < 600; y++)
        for (int x = 0; x < 800; x++) {
            const int row = y / 16, col = x / 16;
            const uint8_t c = ch[y * 800 + x];
            const uint8_t w = row < 37 ? uint8_t(want[row][col]) : ' ';
            if (c != w && bad_cells++ < 5) std::printf("  %s: cell (%d, %d) '%c', want '%c'\n", name, col, row, c, w);
            const bool ink = FONT[c * 8 + (y % 16) / 2] >> (7 - (x % 16) / 2) & 1;
            const bool lit = px[y * 800 + x] != 0x000040;
            if (ink != lit && bad_px++ < 5) std::printf("  %s: pixel (%d, %d) ink %d\n", name, x, y, ink);
        }
    CHECK(bad_cells == 0, "%s: %d pixels in the wrong character cell", name, bad_cells);
    CHECK(bad_px == 0, "%s: %d pixels not the font's", name, bad_px);
}

template <typename Setup>
static void scenario(const char *name, Setup setup, unsigned want, bool screen) {
    Bench b;
    b.slave.mem = EDID;
    setup(b.slave);
    b.reset();
    while (b.status() == 0 && b.clocks < 6000000) b.tick();
    CHECK(b.status() == want, "%s: status %u, want %u (after %ld clocks)", name, b.status(), want, b.clocks);
    for (auto &e : b.timing.errors) CHECK(false, "%s: I2C timing: %s", name, e.c_str());
    if (want == 1) {
        CHECK(b.top->p_reads.get<unsigned>() == 1, "%s: reads %u", name, b.top->p_reads.get<unsigned>());
        CHECK(b.slave.bytes_sent == 256, "%s: the sink sent %d bytes", name, b.slave.bytes_sent);
        CHECK(b.slave.stops >= 2 && b.slave.starts >= 2, "%s: %d STARTs, %d STOPs", name, b.slave.starts,
              b.slave.stops);
    }
    if (screen) check_screen(b, name);
    std::printf("%s: status %u after %ld clocks (%.1f ms)\n", name, b.status(), b.clocks, b.clocks / 40e3);
}

int main() {
    EDID = read_hex(FPGA + "/tests/data/edid_hdmi_audio.hex");
    FONT = read_font(FPGA + "/gen/glass_font.vh");
    CHECK(EDID.size() == 256, "the sample EDID has %zu bytes", EDID.size());
    scenario("plain", [](DdcSlave &) {}, 1, true);
    scenario("stretching", [](DdcSlave &s) { s.stretch = 2000; }, 1, false);
    scenario("no sink", [](DdcSlave &s) { s.present = false; }, 2, true);
    scenario("stuck sink", [](DdcSlave &s) { s.stuck = true; }, 1, false);
    scenario("SCL held low", [](DdcSlave &s) { s.scl_stuck = true; }, 5, false);
    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("edid_core: all scenarios pass\n");
    return 0;
}
