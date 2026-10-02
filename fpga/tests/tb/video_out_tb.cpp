// Whole-frame testbench for rtl/video/zm_video_out.v: the compositor, the plane
// mixer, the display buffers, zm_vtiming and the scanout, in two clock domains.
//
//   video_out_tb <comp clocks> <pixel clocks> <dump dir> <frame>...
//
// The compositor's clock runs at <comp clocks>/<pixel clocks> times the pixel
// clock. Recorded frames are replayed through the compositor as fast as it
// takes them (video_replay.h, no read-back), while the scanout shows them in
// real time; frame n of the replay is the n-th frame on the wire. Every pixel
// clock, the RGB/DE/HSYNC/VSYNC outputs are checked against VESA 800x600@60
// and the browser's picture (f<N>.mix) doubled vertically between 20-line
// black bars. Exits non-zero on any difference, or if the scanout ever had to
// show a line the compositor had not finished (`underrun`).
#include <cstdio>
#include <cstdlib>
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
    long x = 0, y = 0, frame = 0, bad_px = 0, bad_sync = 0;

    void pixel(const Top& t) {
        bool de = t.p_de.get<bool>(), hs = t.p_hsync.get<bool>(), vs = t.p_vsync.get<bool>();
        if (!locked && !(locked = de)) return;
        bool want_de = x < 800 && y < 600, want_hs = x >= 840 && x < 968, want_vs = y >= 601 && y < 605;
        if ((de != want_de || hs != want_hs || vs != want_vs) && ++bad_sync <= 5)
            std::printf("FAIL frame %ld (%ld, %ld): de %d hs %d vs %d\n", frame, x, y, de, hs, vs);
        if (size_t(frame) < frames.size()) check_rgb(t);
        if (++x == kHTotal) x = 0, y++;
        if (y == kVTotal) y = 0, frame++;
    }

    void check_rgb(const Top& t) {
        uint8_t want[3] = {0, 0, 0};
        if (x < 800 && y >= kTop && y < kTop + 2 * vd::LINES) {
            const uint8_t* m = &frames[size_t(frame)]->mix[(size_t((y - kTop) / 2) * vd::ROW + size_t(x)) * 3];
            want[0] = m[0], want[1] = m[1], want[2] = m[2];
        }
        uint32_t r = t.p_r.get<uint32_t>(), g = t.p_g.get<uint32_t>(), b = t.p_b.get<uint32_t>();
        if ((r == want[0] && g == want[1] && b == want[2]) || ++bad_px > 5) return;
        std::printf("FAIL frame %ld (%ld, %ld): rgb %02x%02x%02x, want %02x%02x%02x\n", frame, x, y, r, g, b,
                    want[0], want[1], want[2]);
    }
};

Screen screen;
long num = 2, den = 1, phase = 0;

void pixel_tick(Top& t) {
    t.p_pix__clk.set(true);
    t.step();
    t.p_pix__clk.set(false);
    t.step();
}

int report(Rig& rig, const vd::Replay<Rig>& r, size_t n) {
    bool underrun = rig.top.p_underrun.get<bool>(), hazard = rig.top.p_mix__hazard.get<bool>();
    bool ok = size_t(screen.frame) >= n && !screen.bad_px && !screen.bad_sync && !underrun && !hazard &&
              !r.bad_regs && !r.bad_pixels && !rig.bad_reads && !rig.top.p_overflow.get<bool>();
    std::printf("%zu frames at %ld:%ld compositor:pixel clocks: %ld bad pixels, %ld bad sync, %ld bad registers, "
                "underrun %d, hazard %d -> %s\n",
                n, num, den, screen.bad_px, screen.bad_sync, r.bad_regs, int(underrun), int(hazard),
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
}  // namespace

int main(int argc, char** argv) {
    if (argc < 5) {
        std::fprintf(stderr, "usage: video_out_tb <comp clocks> <pixel clocks> <dump dir> <frame>...\n");
        return 2;
    }
    num = std::atol(argv[1]), den = std::atol(argv[2]);
    static std::vector<vd::Frame> frames;
    if (!load_frames(argv[3], argc - 4, argv + 4, frames)) return 2;
    static Rig rig;  // its constructor reset the compositor's domain
    rig.top.p_pix__rst.set(true);
    pixel_tick(rig.top);
    rig.top.p_pix__rst.set(false);
    // Pixel clocks in step with the compositor's: `den` pixel edges every `num` of its edges.
    rig.after_cycle = [] {
        for (phase += den; phase >= num; phase -= num) {
            pixel_tick(rig.top);
            screen.pixel(rig.top);
        }
    };
    static vd::Replay<Rig> r(rig);
    r.check_passes = false;
    for (auto& f : frames) {
        r.f = &f;
        r.run();
    }
    for (long limit = rig.cycles + 4L * kHTotal * kVTotal * num / den; size_t(screen.frame) < frames.size();)
        if (rig.cycle(), rig.cycles > limit) break;
    return report(rig, r, frames.size());
}
