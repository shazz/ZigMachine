// The memory behind zm_blit's master ports for blitter_tb.cpp: a byte array at the machine's
// linear addresses, answered like a loaded DDR in `random` / `deep` mode, and the contract
// check a memory cannot make by itself (no write taken over an unanswered read of its bytes).
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <vector>

#include "zm_blit.cc"

static cxxrtl_design::p_zm__blit top;
static const uint32_t LO = 0x100000, HI = 0x900000, VIDEO = 0x500000, REGS_END = VIDEO + 0x100;
static const uint8_t PAL[8] = {0, 1, 2, 0x55, 0xAA, 0xFF, 0x0F, 0xF0};
static std::vector<uint8_t> mem(HI, 0);
static uint64_t rng = 1, lcg = 12345;
static bool randomize = false, deep = false;
static long now = 0, bad = 0, pending_until = 0;
struct Rsp { long due; uint32_t data, addr; };
static std::deque<Rsp> rsp_q;

static uint64_t next() { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }
static unsigned rnd(unsigned n) { lcg = lcg * 6364136223846793005ull + 1442695040888963407ull; return unsigned(lcg >> 33) % n; }

static void seed(uint64_t n) {
    rng = n * 0x9E3779B97F4A7C15ull + 1;
    for (uint32_t a = LO; a < HI; a++) {
        uint8_t v = uint8_t(next() >> 16);
        mem[a] = (v & 0xE0) == 0 ? v : PAL[v & 7];
    }
}

static uint64_t hash() {
    uint64_t h = 0xcbf29ce484222325ull;
    for (uint32_t a = LO; a < HI; a += 8) {
        if (a >= VIDEO && a < REGS_END) continue;
        uint64_t w;
        memcpy(&w, &mem[a], 8);
        h = (h ^ w) * 0x100000001b3ull;
        h ^= h >> 29;
    }
    return h;
}

static bool in_window(uint32_t a) { return a >= LO && a < HI; }

static void tick() {
    bool rr = !randomize || rnd(4) != 0, wr = !randomize || rnd(4) != 0;
    top.p_rd__req__ready.set(rr);
    top.p_wr__req__ready.set(wr);
    bool rsp = !rsp_q.empty() && rsp_q.front().due <= now;
    top.p_rd__rsp__valid.set(rsp);
    top.p_rd__rsp__data.set<uint32_t>(rsp ? rsp_q.front().data : 0xDEADBEEF);
    top.p_wr__pending.set(now < pending_until);
    top.step();
    if (rsp) rsp_q.pop_front();
    if (top.p_rd__req__valid.get<bool>() && rr) {
        uint32_t a = top.p_rd__req__addr.get<uint32_t>();
        if (!in_window(a)) bad++;
        else {
            uint32_t w;
            memcpy(&w, &mem[a & ~3u], 4);
            long late = deep ? 16 + long(rnd(16)) : randomize ? long(rnd(4)) : 0;
            rsp_q.push_back({now + 1 + late, w, a});
        }
    }
    if (top.p_wr__req__valid.get<bool>() && wr) {
        uint32_t a = top.p_wr__req__addr.get<uint32_t>(), d = top.p_wr__req__data.get<uint32_t>();
        unsigned strb = top.p_wr__req__strb.get<unsigned>();
        for (const Rsp &r : rsp_q)  // an unanswered earlier read of one of these bytes
            if ((r.addr & ~3u) == a && (strb >> (r.addr & 3) & 1)) {
                std::printf("write %06x strb %x taken over the unanswered read of %06x\n", a, strb, r.addr);
                bad++;
            }
        if (!in_window(a) || (a & 3) || strb == 0 || strb > 15) bad++;
        else
            for (int i = 0; i < 4; i++)
                if (strb >> i & 1) mem[a + i] = uint8_t(d >> (8 * i));
        pending_until = now + 1 + (randomize ? long(rnd(6)) : 0);
    }
    top.p_clk.set(true);
    top.step();
    top.p_clk.set(false);
    top.step();
    now++;
}

