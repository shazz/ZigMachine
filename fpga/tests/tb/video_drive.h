// Drives rtl/video/zm_video_comp.v under CXXRTL: clocking, the CPU port, pass
// commands, the line-buffer read port, and the memory behind the read port.
//
// The memory model answers in order after a pseudo-random 1..8 clocks and
// refuses requests on a pseudo-random quarter of clocks, so the fetcher is
// exercised against a port that stalls, as an AXI HP port to DDR will.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <vector>

#include "zm_video_comp.cc"

namespace vd {

class Rig {
public:
    cxxrtl_design::p_zm__video__comp top;
    const std::vector<uint8_t>* mem = nullptr;  // region offset 0 ..
    long cycles = 0, bad_reads = 0;
    long compose_cycles = 0;  // clocks inside BG/PLANE passes only

    Rig() {
        top.p_rst.set(true);
        cycle();
        top.p_rst.set(false);
    }

    void cycle() {
        top.step();
        serve_memory();
        top.p_clk.set(true);
        top.step();
        top.p_clk.set(false);
        top.step();
        cycles++;
    }

    void cpu_write(uint32_t byte_off, uint32_t v) {
        top.p_cpu__we.set(true);
        top.p_cpu__waddr.set<uint32_t>(byte_off >> 2);
        top.p_cpu__be.set<uint32_t>(0xF);
        top.p_cpu__wdata.set<uint32_t>(v);
        cycle();
        top.p_cpu__we.set(false);
    }

    uint32_t reg_read(int word) {
        top.p_cpu__rword.set<uint32_t>(uint32_t(word));
        top.step();
        return top.p_cpu__rdata.get<uint32_t>();
    }

    // Issue one command; BG/PLANE wait for pass_done, LATCH takes one clock.
    void command(int op, int plane, int line) {
        while (!top.p_cmd__ready.get<bool>()) cycle();
        top.p_cmd__valid.set(true);
        top.p_cmd__op.set<uint32_t>(uint32_t(op));
        top.p_cmd__plane.set<uint32_t>(uint32_t(plane));
        top.p_cmd__line.set<uint32_t>(uint32_t(line));
        cycle();
        top.p_cmd__valid.set(false);
        if (op == 2) return;
        long t0 = cycles;
        while (!top.p_pass__done.get<bool>()) {
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

    // The line buffer as 800 RGBA pixels.
    void read_line(uint32_t* out) {
        for (int x = 0; x < ZM_PHYSICAL_WIDTH; x++) {
            top.p_lb__raddr.set<uint32_t>(uint32_t(x));
            cycle();
            uint64_t pair = top.p_lb__rdata.get<uint64_t>();
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
            top.p_mem__rsp__data.set<uint32_t>(word_at(queue_.front().addr));
            queue_.pop_front();
        }
        bool ready = (rnd() & 3) != 0;
        top.p_mem__req__ready.set(ready);
        if (ready && top.p_mem__req__valid.get<bool>())
            queue_.push_back({top.p_mem__req__addr.get<uint32_t>(), cycles + 1 + long(rnd() & 7)});
    }
};

}  // namespace vd
