// Replay testbench for rtl/video/zm_video_comp.v against the wasm machine.
//
//   video_comp_tb <dump dir> <frame>...
//
// For each frame recorded by tools/video_dump.py it runs the compositor line by
// line: the BG pass, then a PLANE pass per enabled plane. Before every pass it
// plays the CPU: it writes, through the CPU port, each register / palette /
// BEAM word whose value differs from what the machine held when it computed
// that pass of that line. After every pass it reads the line buffer back and
// compares all 800 pixels with the machine's PFB row. The words the compositor
// writes itself (BACKGROUND, BEAM_COUNT, BEAM_DROPPED, FRAME) are checked
// against the machine's next state record instead of being overwritten unseen.
// Exits non-zero on any difference.
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "video_dump.h"
#include "video_drive.h"

namespace {

// The register words the compositor stores (zm_video_regs.v IMPL).
const int kRegWords[] = {0, 1, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 25, 26};
// ... and the ones it writes itself.
const int kOwnWords[] = {ZM_REG_BACKGROUND / 4, ZM_REG_BEAM_COUNT / 4, ZM_REG_BEAM_DROPPED / 4, ZM_REG_FRAME / 4};

struct Replay {
    vd::Rig rig;
    const vd::Frame* f = nullptr;
    uint32_t pal[vd::PAL_WORDS] = {}, beam[vd::BEAM_WORDS] = {};  // what the RTL RAMs hold
    long bad_pixels = 0, bad_regs = 0;
    long max_line_cycles = 0;  // compose clocks only: no readout, no CPU writes

    void apply_regs(const vd::State& s) {
        for (int w : kRegWords)
            if (rig.reg_read(w) != s[size_t(w)]) rig.cpu_write(uint32_t(w) * 4, s[size_t(w)]);
    }
    void apply_ram(const vd::State& s, int first, int n, uint32_t* shadow, uint32_t off) {
        for (int i = 0; i < n; i++) {
            if (shadow[i] == s[size_t(first + i)]) continue;
            shadow[i] = s[size_t(first + i)];
            rig.cpu_write(off + uint32_t(i) * 4, shadow[i]);
        }
    }
    void check_own(const vd::State& want, int y) {
        for (int w : kOwnWords) {
            uint32_t got = rig.reg_read(w);
            if (got == want[size_t(w)] || ++bad_regs > 10) continue;
            std::printf("FAIL line %d: register word %d = %08x, machine %08x\n", y, w, got, want[size_t(w)]);
        }
    }
    void compare(int k, int y) {
        uint32_t line[vd::ROW];
        rig.read_line(line);
        const uint32_t* want = f->row(k, y);
        for (int x = 0; x < vd::ROW; x++) {
            if (line[x] == want[x]) continue;
            if (++bad_pixels <= 10)
                std::printf("FAIL pass %d line %d x %d: rtl %08x machine %08x\n", k, y, x, line[x], want[x]);
        }
    }
    void bg_line(int y) {
        apply_regs(*f->consumed(0, y));
        apply_ram(*f->consumed(0, y), vd::BEAM0, vd::BEAM_WORDS, beam, ZM_OFF_BEAM_TABLE);
        rig.command(0, 0, y);
        // The machine's state just after this line: next line's PRE, or the end.
        vd::StateP next = y + 1 < vd::LINES ? f->pre[0][y + 1] : f->end[0];
        if (next) check_own(*next, y);
        compare(0, y);
    }
    void plane_line(int p, int y) {
        const int k = p + 1;
        if (y == 0) {
            apply_regs(*f->start[k]);
            rig.command(2, p, 0);
        }
        const vd::State& s = *f->consumed(k, y);
        apply_regs(s);
        apply_ram(s, vd::PAL0 + p * ZM_PAL_ENTRIES, ZM_PAL_ENTRIES, pal + p * ZM_PAL_ENTRIES, ZM_OFF_PAL + p * ZM_PAL_BYTES);
        rig.command(1, p, y);
        compare(k, y);
    }
    void run() {
        rig.mem = &f->mem;
        for (int y = 0; y < vd::LINES; y++) {
            long c0 = rig.compose_cycles;
            bg_line(y);
            for (int p = 0; p < ZM_NB_PLANES; p++)
                if ((f->planes >> p) & 1) plane_line(p, y);
            if (rig.compose_cycles - c0 > max_line_cycles) max_line_cycles = rig.compose_cycles - c0;
        }
    }
};

}  // namespace

int main(int argc, char** argv) {
    if (argc < 3) {
        std::fprintf(stderr, "usage: video_comp_tb <dump dir> <frame>...\n");
        return 2;
    }
    static Replay r;  // the CXXRTL model is large: keep it off the stack
    int failed = 0;
    for (int i = 2; i < argc; i++) {
        static vd::Frame f;
        f = vd::Frame{};
        if (!vd::load(argv[1], std::atol(argv[i]), f)) {
            std::printf("FAIL cannot load frame %s from %s\n", argv[i], argv[1]);
            return 2;
        }
        r.f = &f;
        r.bad_pixels = r.bad_regs = r.max_line_cycles = 0;
        r.run();
        bool ok = r.bad_pixels == 0 && r.bad_regs == 0 && r.rig.bad_reads == 0 && !r.rig.top.p_overflow.get<bool>();
        std::printf("frame %s: planes %x vram_changed %d: %ld bad pixels, %ld bad registers, %ld bad reads, "
                    "overflow %d, max %ld compose clocks/line -> %s\n",
                    argv[i], f.planes, f.vram_changed, r.bad_pixels, r.bad_regs, r.rig.bad_reads,
                    int(r.rig.top.p_overflow.get<bool>()), r.max_line_cycles, ok ? "MATCH" : "DIFFER");
        failed += !ok;
    }
    return failed ? 1 : 0;
}
