// Loads one frame recorded by fpga/tools/video_dump (vdump) and rebuilds, from
// its delta records, the state the wasm machine consumed at every pass and
// line. Pass 0 is the background (hwClear), pass p + 1 is hwRenderPlane(p).
#pragma once
#include <array>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "zm_memmap.h"

namespace vd {

constexpr int REG_WORDS = 32, PAL_WORDS = ZM_NB_PLANES * ZM_PAL_ENTRIES, BEAM_WORDS = ZM_BEAM_MAX;
constexpr int STATE_WORDS = REG_WORDS + PAL_WORDS + BEAM_WORDS;
constexpr int PAL0 = REG_WORDS, BEAM0 = REG_WORDS + PAL_WORDS;
constexpr int LINES = ZM_RASTER_HEIGHT, PASSES = 1 + ZM_NB_PLANES;
constexpr int ROW = ZM_RASTER_WIDTH;
enum Kind { PRE = 1, POST = 2, PASS_START = 3, PASS_END = 4 };

using State = std::array<uint32_t, STATE_WORDS>;
using StateP = std::shared_ptr<const State>;

struct Frame {
    unsigned planes = 0;                   // enabled-plane mask
    int vram_changed = 0;
    std::vector<uint8_t> mem;              // region offset 0 ..
    std::vector<uint32_t> pfb;             // after clear, then after each enabled plane
    std::vector<uint8_t> mix;              // the browser's picture, 800x280 RGB (tools/video_mix.py)
    StateP start[PASSES], end[PASSES];
    StateP pre[PASSES][LINES], post[PASSES][LINES];

    // The machine's PFB, row y, after pass k (k = 0 clear, else plane k - 1).
    const uint32_t* row(int k, int y) const {
        int idx = k > 0;  // the clear comes first, then one PFB per enabled plane
        for (int p = 0; p < k - 1; p++) idx += (planes >> p) & 1;
        return &pfb[(size_t(idx) * LINES + y) * ROW];
    }
    // What pass k consumed on line y: its handler's POST state, else the
    // previous line's, else the state at the start of the pass.
    StateP consumed(int k, int y) const {
        for (int l = y; l >= 0; l--)
            if (post[k][l]) return post[k][l];
        return start[k];
    }
};

inline bool slurp(const std::string& path, std::vector<uint8_t>& out) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return false;
    std::fseek(f, 0, SEEK_END);
    out.resize(size_t(std::ftell(f)));
    std::fseek(f, 0, SEEK_SET);
    bool ok = std::fread(out.data(), 1, out.size(), f) == out.size();
    std::fclose(f);
    return ok;
}

template <typename T> T rd(const std::vector<uint8_t>& b, size_t& at) {
    T v{};
    for (size_t i = 0; i < sizeof(T); i++) v |= T(b[at + i]) << (8 * i);
    at += sizeof(T);
    return v;
}

// Replay the delta records in order; each one snapshots the running state.
inline bool parse_records(const std::vector<uint8_t>& b, Frame& f) {
    State m{};
    for (size_t at = 0; at < b.size();) {
        int kind = rd<uint8_t>(b, at), pass = rd<uint8_t>(b, at), line = rd<uint16_t>(b, at);
        int n = rd<uint16_t>(b, at);
        for (int i = 0; i < n; i++) {
            int w = rd<uint16_t>(b, at);
            m[size_t(w)] = rd<uint32_t>(b, at);
        }
        if (pass >= PASSES || line >= LINES) return false;
        auto s = std::make_shared<const State>(m);
        if (kind == PASS_START) f.start[pass] = s;
        else if (kind == PASS_END) f.end[pass] = s;
        else if (kind == PRE) f.pre[pass][line] = s;
        else if (kind == POST) f.post[pass][line] = s;
    }
    return true;
}

inline bool load(const std::string& dir, long frame, Frame& f) {
    std::string base = dir + "/f" + std::to_string(frame);
    std::vector<uint8_t> rec, pfb;
    FILE* meta = std::fopen((base + ".meta").c_str(), "r");
    if (!meta || std::fscanf(meta, "planes %u vram_changed %d", &f.planes, &f.vram_changed) != 2) return false;
    std::fclose(meta);
    if (!slurp(base + ".mem", f.mem) || !slurp(base + ".rec", rec) || !slurp(base + ".pfb", pfb)) return false;
    if (!slurp(base + ".mix", f.mix) || f.mix.size() != size_t(LINES) * ROW * 3) return false;
    f.pfb.resize(pfb.size() / 4);
    for (size_t i = 0; i < f.pfb.size(); i++) {
        size_t at = i * 4;
        f.pfb[i] = rd<uint32_t>(pfb, at);
    }
    return parse_records(rec, f) && f.start[0] != nullptr;
}

}  // namespace vd
