// Whole-frame testbench for rtl/video/zm_video_out.v: the compositor building
// pictures in memory, the double buffer, the scanout fetch, zm_vtiming and the
// scanout, in two clock domains.
//
//   video_out_tb [--starve N] <comp clocks> <pixel clocks> <dump dir> <frame>...
//
// The compositor's clock runs at <comp clocks>/<pixel clocks> times the pixel
// clock. Recorded frames are replayed through the compositor as fast as it
// takes them (video_replay.h, no read-back), each ending in PRESENT, while the
// scanout shows the pictures in real time. Every pixel clock, RGB/DE/HSYNC/VSYNC
// are checked against VESA 800x600@60 and the picture that must be on screen:
// black until the first swap, then the browser's picture (f<N>.mix) of the
// frame shown, doubled vertically between 20-line black bars. A frame on the
// wire is checked against the frame `swaps` names when it starts, so a torn
// picture (two frames on one screen) fails. Exits non-zero on any difference,
// or if the scanout ever showed a line its fetch had not finished (`underrun`).
// `--starve N`: the scanout fetch's port gives a beat at most every N clocks.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "zm_video_out.cc"
#include "video_replay.h"

namespace {

using Top = cxxrtl_design::p_zm__video__out;
using Rig = vd::Rig<Top>;

constexpr int kHTotal = 1056, kVTotal = 628, kTop = 20;

// The expected stream, locked on the first DE after reset (pixel 0, line 0).
struct Screen {
    std::vector<const vd::Frame*> frames;
    bool locked = false;
    long x = 0, y = 0, frame = 0, bad_px = 0, bad_sync = 0, last_whole = -1;
    long showing = 0;  // swaps when this wire frame started: 0 = black, k = frames[k - 1]

    void pixel(const Top& t) {
        bool de = t.p_de.get<bool>(), hs = t.p_hsync.get<bool>(), vs = t.p_vsync.get<bool>();
        if (!locked && !(locked = de)) return;
        if (x == 0 && y == 0) showing = long(t.p_swaps.get<uint32_t>());
        bool want_de = x < 800 && y < 600, want_hs = x >= 840 && x < 968, want_vs = y >= 601 && y < 605;
        if ((de != want_de || hs != want_hs || vs != want_vs) && ++bad_sync <= 5)
            std::printf("FAIL frame %ld (%ld, %ld): de %d hs %d vs %d\n", frame, x, y, de, hs, vs);
        check_rgb(t);
        if (++x == kHTotal) x = 0, y++;
        if (y == kVTotal) y = 0, frame++, last_whole = showing;
    }

    void check_rgb(const Top& t) {
        uint8_t want[3] = {0, 0, 0};
        if (showing > 0 && size_t(showing) <= frames.size() && x < 800 && y >= kTop && y < kTop + 2 * vd::LINES) {
            const vd::Frame* f = frames[size_t(showing - 1)];
            const uint8_t* m = &f->mix[(size_t((y - kTop) / 2) * vd::ROW + size_t(x)) * 3];
            want[0] = m[0], want[1] = m[1], want[2] = m[2];
        }
        uint32_t r = t.p_r.get<uint32_t>(), g = t.p_g.get<uint32_t>(), b = t.p_b.get<uint32_t>();
        if ((r == want[0] && g == want[1] && b == want[2]) || ++bad_px > 5) return;
        std::printf("FAIL frame %ld showing %ld (%ld, %ld): rgb %02x%02x%02x, want %02x%02x%02x\n", frame, showing, x,
                    y, r, g, b, want[0], want[1], want[2]);
    }
};

Screen screen;
long num = 2, den = 1, phase = 0;
vd::ReadChannel scan_rd;

void pixel_tick(Top& t) {
    t.p_pix__clk.set(true);
    t.step();
    t.p_pix__clk.set(false);
    t.step();
}

int report(Rig& rig, const vd::Replay<Rig>& r, size_t n) {
    bool underrun = rig.top.p_underrun.get<bool>();
    bool ok = screen.last_whole == long(n) && !screen.bad_px && !screen.bad_sync && !underrun && !r.bad_regs &&
              !rig.mem.bad && !rig.top.p_overflow.get<bool>();
    std::printf("%zu frames at %ld:%ld compositor:pixel clocks, %ld on the wire: %ld bad pixels, %ld bad sync, "
                "%ld bad registers, underrun %d -> %s\n",
                n, num, den, screen.frame, screen.bad_px, screen.bad_sync, r.bad_regs, int(underrun),
                ok ? "MATCH" : "DIFFER");
    return ok ? 0 : 1;
}

bool load_frames(const char* dir, int n, char** names, std::vector<vd::Frame>& frames) {
    frames.resize(size_t(n));
    for (int i = 0; i < n; i++) {
        if (!vd::load(dir, std::atol(names[i]), frames[size_t(i)])) {
            std::printf("FAIL cannot load frame %s from %s (with its .mix)\n", names[i], dir);
            return false;
        }
        screen.frames.push_back(&frames[size_t(i)]);
    }
    return true;
}

void setup(Rig& rig) {
    Top& t = rig.top;
    t.p_vbase.set<uint32_t>(0);
    t.p_fb0__base.set<uint32_t>(vd::Mem::kFb0);
    t.p_fb1__base.set<uint32_t>(vd::Mem::kFb1);
    t.p_rst.set(true);  // again, now that the picture addresses are set
    rig.cycle();
    t.p_rst.set(false);
    t.p_pix__rst.set(true);
    pixel_tick(t);
    t.p_pix__rst.set(false);
    rig.serve_more = [&rig] {
        Top& u = rig.top;
        rig.mem.serve_read(u.p_sc__req__valid, u.p_sc__req__ready, u.p_sc__req__addr, u.p_sc__req__len,
                           u.p_sc__rsp__valid, u.p_sc__rsp__data, rig.cycles, scan_rd);
    };
    // Pixel clocks in step with the compositor's: `den` pixel edges every `num` of its edges.
    rig.after_cycle = [&rig] {
        for (phase += den; phase >= num; phase -= num) {
            pixel_tick(rig.top);
            screen.pixel(rig.top);
        }
    };
}
}  // namespace

int main(int argc, char** argv) {
    int a = 1;
    if (argc > 2 && !std::strcmp(argv[1], "--starve")) scan_rd.period = std::atoi(argv[2]), a = 3;
    if (argc < a + 4) {
        std::fprintf(stderr, "usage: video_out_tb [--starve N] <comp clocks> <pixel clocks> <dump dir> <frame>...\n");
        return 2;
    }
    num = std::atol(argv[a]), den = std::atol(argv[a + 1]);
    static std::vector<vd::Frame> frames;
    if (!load_frames(argv[a + 2], argc - a - 3, argv + a + 3, frames)) return 2;
    static Rig rig;
    setup(rig);
    static vd::Replay<Rig> r(rig);
    r.check_passes = false;
    for (auto& f : frames) {
        r.f = &f;
        r.run();
    }
    // Until the last picture has been on the wire for one whole frame.
    for (long limit = rig.cycles + 4L * kHTotal * kVTotal * num / den; screen.last_whole < long(frames.size());)
        if (rig.cycle(), rig.cycles > limit) break;
    return report(rig, r, frames.size());
}
