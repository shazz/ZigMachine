// Drives rtl/video/zm_video_comp.v's ports under CXXRTL, on the compositor
// itself or on a top that wraps it with the same port names (zm_video_out):
// clocking, the CPU port, pass commands, the line-buffer read port, and the
// memory behind the read port.
//
// The memory model answers in order after a pseudo-random 1..8 clocks and
// refuses requests on a pseudo-random quarter of clocks, so the fetcher is
// exercised against a port that stalls, as an AXI HP port to DDR will.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <functional>
#include <vector>

namespace vd {

template <typename Top> class Rig {
public:
    Top top;
    const std::vector<uint8_t>* mem = nullptr;  // region offset 0 ..
    long cycles = 0, bad_reads = 0;
    long compose_cycles = 0;  // clocks inside BG/PLANE passes only
    long busy_cycles = 0;     // clocks the compositor is occupied: a pass, a sweep, or one waiting
    std::vector<int> ready_log;  // the line of every line_ready pulse, in order
    std::function<void(bool)> set_clock;  // drives the compositor's clock (and whatever runs with it)
    std::function<void()> after_cycle;    // e.g. the pixel clock, in another domain

    Rig() {
        set_clock = [this](bool v) { top.p_clk.set(v); };
        top.p_rst.set(true);
        cycle();
        top.p_rst.set(false);
    }

    void cycle() {
        top.step();
        serve_memory();
        if (!top.p_cmd__ready.template get<bool>() || top.p_mix__busy.template get<bool>()) busy_cycles++;
        set_clock(true);
        top.step();
        set_clock(false);
        top.step();
        cycles++;
        if (top.p_line__ready.template get<bool>())
            ready_log.push_back(int(top.p_ready__line.template get<uint32_t>()));
        if (after_cycle) after_cycle();
    }

    void cpu_write(uint32_t byte_off, uint32_t v) {
        top.p_cpu__we.set(true);
        top.p_cpu__waddr.template set<uint32_t>(byte_off >> 2);
        top.p_cpu__be.template set<uint32_t>(0xF);
        top.p_cpu__wdata.template set<uint32_t>(v);
        cycle();
        top.p_cpu__we.set(false);
    }

    uint32_t reg_read(int word) {
        top.p_cpu__rword.template set<uint32_t>(uint32_t(word));
        top.step();
        return top.p_cpu__rdata.template get<uint32_t>();
    }

    // Issue one command; BG/PLANE wait for pass_done, LATCH takes one clock.
    // `mix`/`last`: fold the pass into the picture, as the line's last pass.
    void command(int op, int plane, int line, bool mix = false, bool last = false) {
        for (long t0 = cycles; !top.p_cmd__ready.template get<bool>(); cycle())
            if (cycles - t0 > 10000000) {
                std::printf("FAIL the compositor never took command %d for line %d\n", op, line);
                std::exit(1);
            }
        top.p_cmd__valid.set(true);
        top.p_cmd__op.template set<uint32_t>(uint32_t(op));
        top.p_cmd__plane.template set<uint32_t>(uint32_t(plane));
        top.p_cmd__line.template set<uint32_t>(uint32_t(line));
        top.p_cmd__mix.set(mix);
        top.p_cmd__last.set(last);
        cycle();
        top.p_cmd__valid.set(false);
        if (op == 2) return;
        long t0 = cycles;
        while (!top.p_pass__done.template get<bool>()) {
            cycle();
            // A pass that never ends is a failure to report, not a hang (a
            // broken handshake starves the fetcher): no pass needs 20000 clocks.
            if (cycles - t0 > 20000) {
                std::printf("FAIL pass op %d plane %d line %d never finished\n", op, plane, line);
                std::exit(1);
            }
        }
        compose_cycles += cycles - t0 + 1;
        cycle();  // the last line-buffer write lands on this edge
    }

    // Wait until the mixer is idle with nothing pending (the line buffer's read
    // port is the mixer's while it sweeps).
    void settle() {
        long t0 = cycles;
        while (!top.p_cmd__ready.template get<bool>() || top.p_mix__busy.template get<bool>()) {
            cycle();
            if (cycles - t0 > 20000) {
                std::printf("FAIL the mixer never went idle\n");
                std::exit(1);
            }
        }
    }

    // The line buffer as 800 RGBA pixels.
    void read_line(uint32_t* out) {
        settle();
        for (int x = 0; x < ZM_PHYSICAL_WIDTH; x++) {
            top.p_lb__raddr.template set<uint32_t>(uint32_t(x));
            cycle();
            uint64_t pair = top.p_lb__rdata.template get<uint64_t>();
            out[2 * x] = uint32_t(pair);
            out[2 * x + 1] = uint32_t(pair >> 32);
        }
    }

private:
    struct Pending {
        uint32_t addr;
        long due;
    };
    std::deque<Pending> queue_;
    uint32_t lfsr_ = 0xACE1u;

    uint32_t rnd() {
        lfsr_ ^= lfsr_ << 13;
        lfsr_ ^= lfsr_ >> 17;
        lfsr_ ^= lfsr_ << 5;
        return lfsr_;
    }

    uint32_t word_at(uint32_t addr) {
        if (size_t(addr) + 4 > mem->size()) {
            bad_reads++;
            return 0;
        }
        const uint8_t* p = mem->data() + addr;
        return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
    }

    // Before the edge: answer the oldest due request, take a new one if ready.
    void serve_memory() {
        bool rsp = !queue_.empty() && queue_.front().due <= cycles;
        top.p_mem__rsp__valid.set(rsp);
        if (rsp) {
            top.p_mem__rsp__data.template set<uint32_t>(word_at(queue_.front().addr));
            queue_.pop_front();
        }
        bool ready = (rnd() & 3) != 0;
        top.p_mem__req__ready.set(ready);
        if (ready && top.p_mem__req__valid.template get<bool>())
            queue_.push_back({top.p_mem__req__addr.template get<uint32_t>(), cycles + 1 + long(rnd() & 7)});
    }
};

}  // namespace vd
