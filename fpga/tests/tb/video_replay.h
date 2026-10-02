// Replays one recorded frame (video_dump.h) through a top that has the
// compositor's ports (video_drive.h), line by line: the BG pass, then a PLANE
// pass per enabled plane, each folded into the browser's picture as the
// loader stacks its canvases.
//
// Before every pass it plays the CPU: it writes, through the CPU port, each
// register / palette / BEAM word whose value differs from what the machine held
// when it computed that pass of that line. With `check_passes` it then reads
// the line buffer back and compares all 800 pixels with the machine's PFB row
// (which waits for the mixer: the read port is shared). The words the
// compositor writes itself (BACKGROUND, BEAM_COUNT, BEAM_DROPPED, FRAME) are
// checked against the machine's next state record instead of being
// overwritten unseen. `on_line(y)` runs once line y's picture is complete.
#pragma once
#include <cstdio>
#include <functional>

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
    std::function<void(int)> on_line;
    uint32_t pal[PAL_WORDS] = {}, beam[BEAM_WORDS] = {};  // what the RTL RAMs hold
    long bad_pixels = 0, bad_regs = 0;
    long max_line_cycles = 0;  // compose clocks only: no readout, no CPU writes
    long max_line_busy = 0;    // clocks the compositor is occupied, mixing included

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
        uint32_t line[ROW];
        rig.read_line(line);
        const uint32_t* want = f->row(k, y);
        for (int x = 0; x < ROW; x++) {
            if (line[x] == want[x]) continue;
            if (++bad_pixels <= 10)
                std::printf("FAIL pass %d line %d x %d: rtl %08x machine %08x\n", k, y, x, line[x], want[x]);
        }
    }
    int top_plane() const {
        for (int p = ZM_NB_PLANES - 1; p >= 0; p--)
            if ((f->planes >> p) & 1) return p;
        return -1;
    }
    void bg_line(int y) {
        apply_regs(*f->consumed(0, y));
        apply_ram(*f->consumed(0, y), BEAM0, BEAM_WORDS, beam, ZM_OFF_BEAM_TABLE);
        // No plane enabled: the loader shows the cleared PFB on canvas 0.
        rig.command(0, 0, y, f->planes == 0, f->planes == 0);
        // The machine's state just after this line: next line's PRE, or the end.
        StateP next = y + 1 < LINES ? f->pre[0][y + 1] : f->end[0];
        if (next) check_own(*next, y);
        compare(0, y);
    }
    void plane_line(int p, int y) {
        const int k = p + 1;
        if (y == 0) {
            apply_regs(*f->start[k]);
            rig.command(2, p, 0);
        }
        const State& s = *f->consumed(k, y);
        apply_regs(s);
        apply_ram(s, PAL0 + p * ZM_PAL_ENTRIES, ZM_PAL_ENTRIES, pal + p * ZM_PAL_ENTRIES, ZM_OFF_PAL + p * ZM_PAL_BYTES);
        rig.command(1, p, y, true, p == top_plane());
        compare(k, y);
    }
    // Line y's picture is published once the sweep of its last pass has run.
    void finish_line(int y, size_t ready0) {
        for (long t0 = rig.cycles; rig.ready_log.size() < ready0 + size_t(y) + 1; rig.cycle())
            if (rig.cycles - t0 > 10000000) {  // a line that never comes is a failure, not a hang
                std::printf("FAIL line %d was never published\n", y);
                std::exit(1);
            }
        int got = rig.ready_log[ready0 + size_t(y)];
        if (got != y) std::printf("FAIL line_ready for line %d, want %d\n", got, y);
        bad_pixels += got != y;
        if (on_line) on_line(y);
    }
    void run() {
        rig.mem = &f->mem;
        size_t ready0 = rig.ready_log.size();
        long busy0 = rig.busy_cycles;
        for (int y = 0; y < LINES; y++) {
            long c0 = rig.compose_cycles;
            bg_line(y);
            for (int p = 0; p < ZM_NB_PLANES; p++)
                if ((f->planes >> p) & 1) plane_line(p, y);
            if (rig.compose_cycles - c0 > max_line_cycles) max_line_cycles = rig.compose_cycles - c0;
            // The previous line's sweep overlaps this line's passes: settle it now.
            if (y > 0) finish_line(y - 1, ready0);
            long busy = rig.busy_cycles - busy0;
            busy0 = rig.busy_cycles;
            if (y > 0 && busy > max_line_busy) max_line_busy = busy;
        }
        finish_line(LINES - 1, ready0);
    }
};

}  // namespace vd
