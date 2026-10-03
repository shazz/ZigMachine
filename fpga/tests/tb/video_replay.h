// Replays one recorded frame (video_dump.h) through a top that has the
// compositor's ports (video_drive.h), in the machine's own order: the BG pass
// of every line (hwClear), then, for each enabled plane, LATCH and a PLANE pass
// of every line folded into the picture (hwRenderPlane), or a MIX pass of every
// line when no plane is enabled; then PRESENT.
//
// Before every pass it plays the CPU: it writes, through the CPU port, each
// register / palette / BEAM word whose value differs from what the machine held
// when it computed that pass of that line. With `check_passes` it then reads
// the PFB row the pass left in memory and compares all 800 pixels with the
// machine's. The words the compositor writes itself (BACKGROUND, BEAM_COUNT,
// BEAM_DROPPED, FRAME) are checked against the machine's next state record
// instead of being overwritten unseen. `check_picture` compares the picture
// the frame built with the browser's (f<N>.mix).
#pragma once
#include <cstdio>
#include <cstring>

#include "video_dump.h"  // first: the memmap macros video_drive.h uses
#include "video_drive.h"

namespace vd {

// The register words the compositor stores (zm_video_regs.v IMPL).
const int kRegWords[] = {0, 1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 25, 26};
// ... and the ones it writes itself.
const int kOwnWords[] = {ZM_REG_BACKGROUND / 4, ZM_REG_BEAM_COUNT / 4, ZM_REG_BEAM_DROPPED / 4, ZM_REG_FRAME / 4};

template <typename RigT> struct Replay {
    RigT& rig;
    const Frame* f = nullptr;
    bool check_passes = true;
    uint32_t dbase = Mem::kFb0;  // the picture this frame builds (zm_video_comp alone)
    uint32_t pal[PAL_WORDS] = {}, beam[BEAM_WORDS] = {};  // what the RTL RAMs hold
    long bad_pixels = 0, bad_regs = 0, bad_picture = 0;
    long max_pass = 0, frame_clocks = 0, max_line = 0;  // clocks
    long line_clocks[LINES] = {};

    explicit Replay(RigT& r) : rig(r) {}

    void apply_regs(const State& s) {
        for (int w : kRegWords)
            if (rig.reg_read(w) != s[size_t(w)]) rig.cpu_write(uint32_t(w) * 4, s[size_t(w)]);
    }
    void apply_ram(const State& s, int first, int n, uint32_t* shadow, uint32_t off) {
        for (int i = 0; i < n; i++) {
            if (shadow[i] == s[size_t(first + i)]) continue;
            shadow[i] = s[size_t(first + i)];
            rig.cpu_write(off + uint32_t(i) * 4, shadow[i]);
        }
    }
    void check_own(const State& want, int y) {
        for (int w : kOwnWords) {
            uint32_t got = rig.reg_read(w);
            if (got == want[size_t(w)] || ++bad_regs > 10) continue;
            std::printf("FAIL line %d: register word %d = %08x, machine %08x\n", y, w, got, want[size_t(w)]);
        }
    }
    void compare(int k, int y) {
        if (!check_passes) return;
        const uint32_t* want = f->row(k, y);
        for (int x = 0; x < ROW; x++) {
            uint32_t got = rig.mem.word_at(uint32_t(ZM_OFF_PFB + (y * ROW + x) * 4));
            if (got == want[x]) continue;
            if (++bad_pixels <= 10)
                std::printf("FAIL pass %d line %d x %d: rtl %08x machine %08x\n", k, y, x, got, want[x]);
        }
    }
    void pass(int op, int p, int y, bool first) {
        long c = rig.command(op, p, y, op != 0, first);
        line_clocks[y] += c;
        if (c > max_pass) max_pass = c;
    }
    void bg_line(int y) {
        apply_regs(*f->consumed(0, y));
        apply_ram(*f->consumed(0, y), BEAM0, BEAM_WORDS, beam, ZM_OFF_BEAM_TABLE);
        pass(0, 0, y, false);
        // The machine's state just after this line: next line's PRE, or the end.
        StateP next = y + 1 < LINES ? f->pre[0][y + 1] : f->end[0];
        if (next) check_own(*next, y);
        compare(0, y);
    }
    void plane_line(int p, int y, bool first) {
        const int k = p + 1;
        const State& s = *f->consumed(k, y);
        apply_regs(s);
        apply_ram(s, PAL0 + p * ZM_PAL_ENTRIES, ZM_PAL_ENTRIES, pal + p * ZM_PAL_ENTRIES, ZM_OFF_PAL + p * ZM_PAL_BYTES);
        pass(1, p, y, first);
        compare(k, y);
    }
    void check_picture() {
        for (int y = 0; y < LINES; y++)
            for (int x = 0; x < ROW; x++) {
                uint32_t got = rig.mem.word_at(dbase + uint32_t(y * ROW + x) * 4);
                const uint8_t* m = &f->mix[(size_t(y) * ROW + size_t(x)) * 3];
                uint32_t want = uint32_t(m[0]) | uint32_t(m[1]) << 8 | uint32_t(m[2]) << 16;
                if (got == want || ++bad_picture > 5) continue;
                std::printf("FAIL picture line %d x %d: rtl %06x browser %06x\n", y, x, got, want);
            }
    }
    void run() {
        std::memcpy(rig.mem.bytes.data(), f->mem.data(), std::min(f->mem.size(), size_t(Mem::kFb0)));
        // The dump holds this frame's cleared PFB: poison it, so every row must come from a pass.
        std::memset(rig.mem.bytes.data() + ZM_OFF_PFB, 0xA5, ZM_PFB_BYTES);
        std::memset(line_clocks, 0, sizeof line_clocks);
        long t0 = rig.cycles;
        for (int y = 0; y < LINES; y++) bg_line(y);
        bool first = true;
        for (int p = 0; p < ZM_NB_PLANES; p++) {
            if (!((f->planes >> p) & 1)) continue;
            apply_regs(*f->start[p + 1]);
            rig.command(2, p, 0);
            for (int y = 0; y < LINES; y++) plane_line(p, y, first);
            first = false;
        }
        if (first)  // no plane enabled: the loader shows the cleared PFB on canvas 0
            for (int y = 0; y < LINES; y++) pass(3, 0, y, true);
        rig.command(4, 0, 0);
        frame_clocks = rig.cycles - t0;
        for (long c : line_clocks) max_line = c > max_line ? c : max_line;
    }
};

}  // namespace vd
