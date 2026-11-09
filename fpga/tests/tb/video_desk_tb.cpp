// The desk mode on the wire (HW 1.17.0, docs/GEM_DESK_MODE.md §7): zm_video_out with no pass
// at all, its CPU port playing a cart that switches RESOLUTION to RES_DESK and back mid-frame.
//
//   video_desk_tb [--starve N] [--desk-only] <comp clocks> <pixel clocks> <ref dir> <FB_BASE>
//
// <ref dir> holds tools/desk_ref.zig's plane.bin, pal.bin and desk.rgba: the MACHINE's picture of
// that plane through that palette (hwRenderDesk's halves). Plane 0 goes into memory at FB_BASE
// & ~7 (the region is at bus address 0), palette 0 through the CPU port: every entry first with
// a wrong green, then green alone by a byte store (the other bytes of the word are garbage), and
// palette 1 as garbage, which the mirror must not take. Both pictures hold a pattern, so a
// normal frame is checkable without the compositor.
//
// The script: wire frames 1-2 normal; RES_DESK written at line 300 of frame 2, so frames 3-4
// are desk; RES_PLANES written at line 100 of frame 4 (inside the desk picture), so 5-6 are
// normal; RES_DESK again at line 600 of frame 5, after its VBL: frame 6 stays normal, 7 is desk.
// A frame's mode is the last value written before its VBL (output line 580). Every pixel
// clock is checked: syncs, the bars, the picture, from frame 0 (both clocks leave reset
// together here, so the fetch starts in phase). `underrun` must never rise, across both switches. --desk-only: desk from the first VBL, 3 frames,
// and --starve then starts with them (the desk's deadline alone).
//
// The bars of a desk frame are REG_BACKGROUND (R in byte 0, alpha never shown); a normal frame's
// border is the picture's. A frame's colour is, like its mode, the last written before its VBL,
// and holds through its bottom bar (lines 540..599, past the VBL): A from the start; at line 300
// of desk frame 3, R and B alone by byte stores (frame 3 keeps A to its last line, 4 shows B);
// C at line 590 of frame 6, after its VBL (desk frame 7 still shows B). A desk pixel inside the
// picture is never the bars' colour (the palette has none): one that is, where the fetch was
// late, is counted ("bar pixels in the picture"), as an underrun must show black.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "zm_memmap.h"
#include "zm_video_out.cc"
#include "video_drive.h"

namespace {

using Top = cxxrtl_design::p_zm__video__out;
using Rig = vd::Rig<Top>;
constexpr int kHTotal = 1056, kVTotal = 628, kTop = 20, kDeskTop = 60, kDeskLeft = 80, kVbl = 580;
constexpr int kW = 640, kH = 480;

std::vector<uint8_t> g_plane, g_pal, g_desk;

uint32_t pattern(long x, long y) {  // a normal picture's {0, B, G, R} word
    return uint32_t((x ^ (y * 3)) & 0xFF) | uint32_t((y + x / 3) & 0xFF) << 8 | uint32_t(((x >> 8) + y * 7) & 0xFF) << 16;
}

struct Screen {
    bool locked = false, seen_underrun = false, written_desk = false, next_desk = false, desk = false;  // desk: this frame's mode
    uint32_t written_bg = 0, next_bg = 0, bg = 0;  // REG_BACKGROUND: as stored, at the VBL, this frame's
    long x = 0, y = 0, frame = 0, bad_px = 0, bad_sync = 0, desk_frames = 0, normal_frames = 0, bars_in_pic = 0;

    bool in_picture() const { return y >= kDeskTop && y < kDeskTop + kH && x >= kDeskLeft && x < kDeskLeft + kW; }

    void expect(uint8_t want[3]) const {
        want[0] = want[1] = want[2] = 0;
        if (x >= 800 || y >= 600) return;
        if (desk) {
            if (!in_picture()) {
                want[0] = uint8_t(bg), want[1] = uint8_t(bg >> 8), want[2] = uint8_t(bg >> 16);
                return;
            }
            const uint8_t* m = &g_desk[(size_t(y - kDeskTop) * kW + size_t(x - kDeskLeft)) * 4];
            want[0] = m[0], want[1] = m[1], want[2] = m[2];
            return;
        }
        if (y < kTop || y >= kTop + 2 * ZM_RASTER_HEIGHT) return;
        uint32_t w = pattern(x, (y - kTop) / 2);
        want[0] = uint8_t(w), want[1] = uint8_t(w >> 8), want[2] = uint8_t(w >> 16);
    }

    void pixel(const Top& t) {
        bool de = t.p_de.get<bool>(), hs = t.p_hsync.get<bool>(), vs = t.p_vsync.get<bool>();
        if (!locked && !(locked = de)) return;
        if (x == 0 && y == 0) desk = next_desk, bg = next_bg;
        bool want_de = x < 800 && y < 600, want_hs = x >= 840 && x < 968, want_vs = y >= 601 && y < 605;
        if ((de != want_de || hs != want_hs || vs != want_vs) && ++bad_sync <= 5)
            std::printf("FAIL frame %ld (%ld, %ld): de %d hs %d vs %d\n", frame, x, y, de, hs, vs);
        if (t.p_underrun.get<bool>() && !seen_underrun && (seen_underrun = true))
            std::printf("underrun first seen at frame %ld (%ld, %ld)\n", frame, x, y);
        uint8_t want[3];
        expect(want);
        uint32_t r = t.p_r.get<uint32_t>(), g = t.p_g.get<uint32_t>(), b = t.p_b.get<uint32_t>();
        if ((r != want[0] || g != want[1] || b != want[2]) && ++bad_px <= 8)
            std::printf("FAIL frame %ld %s (%ld, %ld): rgb %02x%02x%02x, want %02x%02x%02x\n", frame,
                        desk ? "desk" : "normal", x, y, r, g, b, want[0], want[1], want[2]);
        if (desk && in_picture() && (r | g << 8 | b << 16) == (bg & 0xFFFFFFu)) bars_in_pic++;
        if (x == 0 && y == kVbl) next_desk = written_desk, next_bg = written_bg;  // the next frame's, as the VBL samples them
        if (++x == kHTotal) x = 0, y++;
        if (y == kVTotal) y = 0, frame++, (desk ? desk_frames : normal_frames)++;
    }
};

Screen screen;
long num = 5, den = 2, phase = 0;
vd::ReadChannel scan_rd;

void pixel_tick(Top& t) {
    t.p_pix__clk.set(true);
    t.step();
    t.p_pix__clk.set(false);
    t.step();
}

bool load(const char* dir, const char* name, std::vector<uint8_t>& v, size_t n) {
    char path[512];
    std::snprintf(path, sizeof path, "%s/%s", dir, name);
    FILE* f = std::fopen(path, "rb");
    v.resize(n);
    bool ok = f && std::fread(v.data(), 1, n, f) == n;
    if (f) std::fclose(f);
    if (!ok) std::printf("FAIL cannot read %zu bytes of %s\n", n, path);
    return ok;
}

uint32_t pal_word(int i) {
    const uint8_t* p = &g_pal[size_t(i) * 4];
    return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}

// The cart's stores: plane 1's palette as garbage, palette 0 with a wrong green, then green alone.
void play_palettes(Rig& rig, uint32_t fb_base) {
    for (int i = 0; i < 256; i++) rig.cpu_write(ZM_OFF_PAL + ZM_PAL_BYTES + uint32_t(i) * 4, ~pal_word(i));
    for (int i = 0; i < 256; i++) rig.cpu_write(ZM_OFF_PAL + uint32_t(i) * 4, pal_word(i) ^ 0x0000FF00u);
    for (int i = 0; i < 256; i++) rig.cpu_write(ZM_OFF_PAL + uint32_t(i) * 4, (pal_word(i) & 0xFF00u) | 0xA5A500A5u, 0x2);
    rig.cpu_write(ZM_REG_FB_BASE, fb_base);
}

void setup(Rig& rig, uint32_t fb_base) {
    Top& t = rig.top;
    std::memcpy(&rig.mem.bytes[fb_base & ~7u], g_plane.data(), g_plane.size());
    for (uint32_t pic : {vd::Mem::kFb0, vd::Mem::kFb1})
        for (long y = 0; y < ZM_RASTER_HEIGHT; y++)
            for (long x = 0; x < 800; x++) {
                uint32_t w = pattern(x, y), at = pic + uint32_t(y * 800 + x) * 4;
                for (int k = 0; k < 4; k++) rig.mem.bytes[at + uint32_t(k)] = uint8_t(w >> (8 * k));
            }
    t.p_vbase.set<uint32_t>(0);
    t.p_fb0__base.set<uint32_t>(vd::Mem::kFb0);
    t.p_fb1__base.set<uint32_t>(vd::Mem::kFb1);
    t.p_rst.set(true);
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
    play_palettes(rig, fb_base);
    rig.after_cycle = [&rig] {
        for (phase += den; phase >= num; phase -= num) {
            pixel_tick(rig.top);
            screen.pixel(rig.top);
        }
    };
}

// REG_BACKGROUND, the lanes `be` selects of `word` (the others keep their value).
void set_background(Rig& rig, uint32_t word, uint32_t be = 0xF) {
    rig.cpu_write(ZM_REG_BACKGROUND, word, be);
    for (int k = 0; k < 4; k++)
        if (be >> k & 1) screen.written_bg = (screen.written_bg & ~(0xFFu << 8 * k)) | (word & 0xFFu << 8 * k);
}

void set_resolution(Rig& rig, int res) {
    rig.cpu_write(ZM_REG_RESOLUTION, uint32_t(res), 0x1);
    screen.written_desk = res == ZM_RES_DESK;
}

// Runs until the wire reaches (frame, line); false if the clocks ran out.
bool run_to(Rig& rig, long frame, long line) {
    for (long limit = rig.cycles + 10L * kHTotal * kVTotal * num / den; screen.frame < frame || screen.y < line;)
        if (rig.cycle(), rig.cycles > limit) return false;
    return true;
}
}  // namespace

int main(int argc, char** argv) {
    int a = 1;
    bool desk_only = false;
    int starve = 1;
    for (; a < argc && argv[a][0] == '-'; a++) {
        if (!std::strcmp(argv[a], "--starve") && a + 1 < argc) starve = std::atoi(argv[++a]);
        else if (!std::strcmp(argv[a], "--desk-only")) desk_only = true;
    }
    if (argc < a + 4) {
        std::fprintf(stderr, "usage: video_desk_tb [--starve N] [--desk-only] <comp> <pixel> <ref dir> <FB_BASE>\n");
        return 2;
    }
    num = std::atol(argv[a]), den = std::atol(argv[a + 1]);
    uint32_t fb_base = uint32_t(std::strtoul(argv[a + 3], nullptr, 0));
    if (!load(argv[a + 2], "plane.bin", g_plane, size_t(kW) * kH) || !load(argv[a + 2], "pal.bin", g_pal, 1024) ||
        !load(argv[a + 2], "desk.rgba", g_desk, size_t(kW) * kH * 4))
        return 2;
    static Rig rig;
    setup(rig, fb_base);
    set_background(rig, 0xC4A05020u);  // A: R 20, G 50, B A0, a garbage alpha
    bool ran = true;
    if (desk_only) {  // starved from the first desk frame on: the desk's own deadline
        set_resolution(rig, ZM_RES_DESK);
        ran = run_to(rig, 1, 0);
        scan_rd.period = starve;
        ran = ran && run_to(rig, 4, 0);
    } else {
        scan_rd.period = starve;
        ran = run_to(rig, 2, 300);
        set_resolution(rig, ZM_RES_DESK);
        ran = ran && run_to(rig, 3, 300);
        set_background(rig, 0xDEADBE7Eu, 0x1);  // B: R 7E ...
        set_background(rig, 0xDE13BEEFu, 0x4);  //    ... and B 13, by byte stores, mid-frame
        ran = ran && run_to(rig, 4, 100);
        set_resolution(rig, ZM_RES_PLANES);
        ran = ran && run_to(rig, 5, 600);
        set_resolution(rig, ZM_RES_DESK);  // after the VBL, before line 0: the next frame stays normal
        ran = ran && run_to(rig, 6, 590);
        set_background(rig, 0x00F0E0D0u);  // C, after the VBL: desk frame 7 still shows B
        ran = ran && run_to(rig, 8, 0);
    }
    bool underrun = rig.top.p_underrun.get<bool>();
    long want_desk = 3, want_normal = desk_only ? 1 : 5;  // frame 0 is normal
    bool ok = ran && !screen.bad_px && !screen.bad_sync && !underrun && !rig.mem.bad &&
              screen.desk_frames == want_desk && screen.normal_frames == want_normal;
    std::printf("%ld frames on the wire (%ld desk, %ld normal) at %ld:%ld: %ld bad pixels, %ld bad sync, underrun %d,"
                " %ld bar pixels in the picture -> %s\n", screen.frame, screen.desk_frames, screen.normal_frames, num,
                den, screen.bad_px, screen.bad_sync, int(underrun), screen.bars_in_pic, ok ? "MATCH" : "DIFFER");
    return ok ? 0 : 1;
}
