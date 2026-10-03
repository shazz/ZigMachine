// Drives rtl/video/zm_video_comp.v's ports under CXXRTL, on the compositor
// itself or on a top that wraps it with the same port names (zm_video_out):
// clocking, the CPU port, pass commands, and the memory behind the read and
// write ports (Mem, video_mem.h).
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <functional>

#include "video_mem.h"

namespace vd {

template <typename Top> class Rig {
public:
    Top top;
    Mem mem;
    long cycles = 0;
    long busy_cycles = 0;  // clocks the compositor is occupied (a command not takeable)
    std::function<void(bool)> set_clock;  // drives the compositor's clock (and whatever runs with it)
    std::function<void()> after_cycle;    // e.g. the pixel clock, in another domain
    std::function<void()> serve_more;     // e.g. the scanout fetch's read port

    Rig() {
        set_clock = [this](bool v) { top.p_clk.set(v); };
        top.p_rst.set(true);
        cycle();
        top.p_rst.set(false);
    }

    void cycle() {
        top.step();
        mem.serve_read(top.p_rd__req__valid, top.p_rd__req__ready, top.p_rd__req__addr, top.p_rd__req__len,
                       top.p_rd__rsp__valid, top.p_rd__rsp__data, cycles, mem.comp_rd);
        mem.serve_write(top, cycles);
        if (serve_more) serve_more();
        if (!top.p_cmd__ready.template get<bool>()) busy_cycles++;
        set_clock(true);
        top.step();
        set_clock(false);
        top.step();
        cycles++;
        if (after_cycle) after_cycle();
    }

    void cpu_write(uint32_t byte_off, uint32_t v) {
        top.p_cpu__we.set(true);
        top.p_cpu__waddr.template set<uint32_t>(byte_off >> 2);
        top.p_cpu__be.template set<uint32_t>(0xF);
        top.p_cpu__wdata.template set<uint32_t>(v);
        top.p_cpu__sel.template set<uint32_t>(region_sel(byte_off));
        cycle();
        top.p_cpu__we.set(false);
    }

    // What the snoop decodes (soc/zm_video_snoop.py): {BEAM table, palettes, register block}.
    static uint32_t region_sel(uint32_t off) {
        uint32_t reg = off < 0x80, pal = off >= ZM_OFF_PAL && off < ZM_OFF_VRAM;
        uint32_t beam = off >= ZM_OFF_BEAM_TABLE && off < ZM_OFF_BEAM_TABLE + ZM_BEAM_MAX * 4;
        return reg | pal << 1 | beam << 2;
    }

    uint32_t reg_read(int word) {
        top.p_cpu__rword.template set<uint32_t>(uint32_t(word));
        top.step();
        return top.p_cpu__rdata.template get<uint32_t>();
    }

    // Issue one command and wait until it is taken; then, for a pass, until
    // `pass_done` (its rows are in memory). Returns the pass's clocks.
    long command(int op, int plane, int line, bool mix = false, bool first = false) {
        top.p_cmd__op.template set<uint32_t>(uint32_t(op));
        top.p_cmd__plane.template set<uint32_t>(uint32_t(plane));
        top.p_cmd__line.template set<uint32_t>(uint32_t(line));
        top.p_cmd__mix.set(mix);
        top.p_cmd__first.set(first);
        top.step();
        // A picture pass may wait for the shown picture to swap: up to a frame.
        wait_for([&] { return top.p_cmd__ready.template get<bool>(); }, "taken", op, line, 20000000);
        top.p_cmd__valid.set(true);
        cycle();
        top.p_cmd__valid.set(false);
        if (op == 2 || op == 4) return 0;
        long t0 = cycles;
        wait_for([&] { return top.p_pass__done.template get<bool>(); }, "finished", op, line, 2000000);
        cycle();
        return cycles - t0;
    }

private:
    template <typename F> void wait_for(F ready, const char* what, int op, int line, long budget) {
        for (long t0 = cycles; !ready(); cycle())
            if (cycles - t0 > budget) {  // a hang is a failure to report, not a wait
                std::printf("FAIL command %d for line %d: never %s\n", op, line, what);
                std::exit(1);
            }
    }
};

}  // namespace vd
