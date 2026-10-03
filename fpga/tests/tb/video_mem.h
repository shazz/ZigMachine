// The memory behind the video pipeline's ports in the CXXRTL testbenches: one
// flat byte array at bus address 0, read in bursts and written in bursts.
//
// Read port (zm_video_fetch.v): a burst request is accepted on a pseudo-random
// three quarters of clocks; its first beat comes 1 to 8 clocks later, and each
// beat after that on a pseudo-random three quarters of clocks, in order, as an
// AXI HP read under load would. Write port (zm_video_rowio.v): the request and
// each beat are accepted on random clocks too, and `wr_busy` stays up a random
// 0 to 7 clocks after the last beat, as an AXI B response would. `fixed_lat`
// replaces all of that by a port that takes everything at once and answers
// after exactly that many clocks, a beat a clock: the throughput figures.
#pragma once
#include <cstdint>
#include <cstdio>
#include <deque>
#include <vector>

namespace vd {

struct ReadChannel {
    struct Burst {
        uint32_t addr;
        int left;
        long due;
    };
    std::deque<Burst> q;
    long beats = 0;
    int period = 1;  // a beat at most every `period` clocks: a starved port
};

class Mem {
public:
    static constexpr uint32_t kSize = 0x01200000;  // the region at 0, the pictures above it
    static constexpr uint32_t kFb0 = 0x01000000, kFb1 = 0x01100000;
    std::vector<uint8_t> bytes = std::vector<uint8_t>(kSize, 0);
    long bad = 0, wr_beats = 0;
    int fixed_lat = -1;  // >= 0: the throughput port
    ReadChannel comp_rd;

    uint64_t beat_at(uint32_t addr) {
        if (addr % 8 || size_t(addr) + 8 > bytes.size()) return bad++, 0;
        uint64_t v = 0;
        for (int i = 7; i >= 0; i--) v = v << 8 | bytes[addr + uint32_t(i)];
        return v;
    }
    void put_beat(uint32_t addr, uint64_t v) {
        if (addr % 8 || size_t(addr) + 8 > bytes.size()) return void(bad++);
        for (int i = 0; i < 8; i++) bytes[addr + uint32_t(i)] = uint8_t(v >> (8 * i));
    }
    uint32_t word_at(uint32_t addr) const {
        return uint32_t(bytes[addr]) | uint32_t(bytes[addr + 1]) << 8 | uint32_t(bytes[addr + 2]) << 16 |
               uint32_t(bytes[addr + 3]) << 24;
    }

    // Before the edge: answer the oldest burst's next beat if due, take a request if ready.
    template <typename V, typename R, typename A, typename L, typename RV, typename RD>
    void serve_read(V& valid, R& ready, A& addr, L& len, RV& rsp_valid, RD& rsp_data, long now, ReadChannel& ch) {
        bool beat = !ch.q.empty() && ch.q.front().due <= now && now % ch.period == 0 &&
                    (fixed_lat >= 0 || (rnd() & 3) != 0);
        rsp_valid.set(beat);
        if (beat) {
            ReadChannel::Burst& b = ch.q.front();
            rsp_data.template set<uint64_t>(beat_at(b.addr));
            b.addr += 8, ch.beats++;
            if (--b.left == 0) ch.q.pop_front();
        }
        bool take = fixed_lat >= 0 || (rnd() & 3) != 0;
        ready.set(take);
        if (take && valid.template get<bool>()) {
            int n = int(len.template get<uint32_t>());
            long lat = fixed_lat >= 0 ? fixed_lat : 1 + long(rnd() & 7);
            ch.q.push_back({addr.template get<uint32_t>(), n, now + lat});
            if (n == 0) bad++;
        }
    }

    template <typename Top> void serve_write(Top& t, long now) {
        bool fast = fixed_lat >= 0;
        bool req_ready = !wr_left_ && (fast || (rnd() & 3) != 0);
        t.p_wr__req__ready.set(req_ready);
        bool dat_ready = wr_left_ > 0 && (fast || (rnd() & 3) != 0);
        t.p_wr__dat__ready.set(dat_ready);
        if (dat_ready && t.p_wr__dat__valid.template get<bool>()) {
            put_beat(wr_addr_, t.p_wr__dat.template get<uint64_t>());
            wr_addr_ += 8, wr_beats++;
            if (--wr_left_ == 0) busy_until_ = now + (fast ? 0 : long(rnd() & 7));
        }
        if (req_ready && t.p_wr__req__valid.template get<bool>()) {
            wr_addr_ = t.p_wr__req__addr.template get<uint32_t>();
            wr_left_ = int(t.p_wr__req__len.template get<uint32_t>());
        }
        t.p_wr__busy.set(wr_left_ > 0 || now < busy_until_);
    }

private:
    uint32_t lfsr_ = 0xACE1u, wr_addr_ = 0;
    int wr_left_ = 0;
    long busy_until_ = 0;

    uint32_t rnd() {
        lfsr_ ^= lfsr_ << 13;
        lfsr_ ^= lfsr_ >> 17;
        lfsr_ ^= lfsr_ << 5;
        return lfsr_;
    }
};

}  // namespace vd
