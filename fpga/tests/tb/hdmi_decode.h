// A reference HDMI sink for tests/tb/hdmi_audio_tb.cpp: it takes the three TMDS
// channels a pixel at a time and does what a sink's front end does, written from
// HDMI 1.3a section 5 without sharing code (or tables) with rtl/hdmi/:
//   - every symbol classified: control token, TERC4, guard band, or video (8b/10b
//     decoded back to a byte);
//   - periods recognised by their preambles (exactly 8 pixels: CTL0 for video,
//     CTL0 + CTL2 for a data island) and guard bands (exactly 2);
//   - each 32-pixel packet rebuilt (header on channel 0 bit 2, subpacket i on
//     channels 1/2 bit i), channel 0 bit 3 checked (0 on a packet's first pixel),
//     and every BCH block checked as a codeword of G(x) = 1 + x^6 + x^7 + x^8:
//     the bits in send order, first = highest degree, must divide exactly.
// Anything else is an error, kept in `errors`. Decoded packets go to `packets`;
// per pixel, `px` says what the sink saw (video and its RGB, or the syncs).
#pragma once
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

struct Packet {
    uint8_t hb[3];
    uint8_t sb[4][7];
};

struct Pixel {
    bool video = false, syncs = false;   // syncs: hs/vs were carried this pixel
    unsigned rgb = 0;
    bool hs = false, vs = false;
};

struct HdmiSink {
    static constexpr unsigned GB_A = 0x2CC, GB_B = 0x133;  // 1011001100, 0100110011
    enum State { CTRL, VGUARD, VIDEO, DGUARD_L, DATA, DGUARD_T } st = CTRL;
    int pre_n = 0, pre_kind = 0, guard_n = 0, k = 0, packets_in_island = 0;
    unsigned hbits = 0, ch0b3 = 0;
    uint64_t sbits[4] = {};
    std::vector<Packet> packets;
    std::vector<std::string> errors;
    long pixel = 0;
    Pixel px;

    void error(const std::string &e) {
        char b[48];
        std::snprintf(b, sizeof b, " (pixel %ld)", pixel);
        if (errors.size() < 20) errors.push_back(e + b);
    }
    static int ctrl(unsigned s) {
        const unsigned t[4] = {0x354, 0x0AB, 0x154, 0x2AB};  // 1101010100 0010101011 0101010100 1010101011
        for (int i = 0; i < 4; i++) if (s == t[i]) return i;
        return -1;
    }
    static int terc4(unsigned s) {
        const unsigned t[16] = {0x29C, 0x263, 0x2E4, 0x2E2, 0x171, 0x11E, 0x18E, 0x13C,
                                0x2CC, 0x139, 0x19C, 0x2C6, 0x28E, 0x271, 0x163, 0x2C3};
        for (int i = 0; i < 16; i++) if (s == t[i]) return i;
        return -1;
    }
    static unsigned video(unsigned s) {  // DVI 1.0 decode
        unsigned d = (s & 0x200) ? ~s & 0xFF : s & 0xFF, o = d & 1;
        for (int i = 1; i < 8; i++) {
            const unsigned x = ((d >> i) ^ (d >> (i - 1))) & 1;
            o |= ((s & 0x100) ? x : !x) << i;
        }
        return o;
    }
    // A BCH codeword (bits in send order) divisible by x^8 + x^7 + x^6 + 1?
    static bool bch_ok(const std::vector<int> &cw) {
        std::vector<int> r(cw);
        const int g[9] = {1, 1, 1, 0, 0, 0, 0, 0, 1};
        for (size_t i = 0; i + 8 < r.size(); i++)
            if (r[i]) for (int j = 0; j < 9; j++) r[i + j] ^= g[j];
        for (size_t i = r.size() - 8; i < r.size(); i++) if (r[i]) return false;
        return true;
    }

    void end_packet() {
        Packet p{};
        std::vector<int> h;
        for (int i = 0; i < 32; i++) h.push_back(hbits >> i & 1);
        if (!bch_ok(h)) error("header ECC");
        for (int b = 0; b < 3; b++) p.hb[b] = uint8_t(hbits >> (8 * b));
        for (int s = 0; s < 4; s++) {
            std::vector<int> c;
            for (int i = 0; i < 64; i++) c.push_back(int(sbits[s] >> i & 1));
            if (!bch_ok(c)) error("subpacket " + std::to_string(s) + " ECC");
            for (int b = 0; b < 7; b++) p.sb[s][b] = uint8_t(sbits[s] >> (8 * b));
        }
        if (ch0b3 != 0xFFFFFFFEu) error("channel 0 bit 3 not 0 then 1s");
        packets.push_back(p);
        packets_in_island++;
    }

    void packet_pixel(int n0, int n1, int n2) {
        if (k == 0) { hbits = 0; ch0b3 = 0; for (auto &s : sbits) s = 0; }
        hbits |= unsigned(n0 >> 2 & 1) << k;
        ch0b3 |= unsigned(n0 >> 3 & 1) << k;
        for (int s = 0; s < 4; s++)
            sbits[s] |= uint64_t(n1 >> s & 1) << (2 * k) | uint64_t(n2 >> s & 1) << (2 * k + 1);
        if (++k == 32) { k = 0; end_packet(); }
    }

    bool dguard(unsigned s0, unsigned s1, unsigned s2) {
        return s1 == GB_B && s2 == GB_B && terc4(s0) >= 12;
    }
    void syncs(int n0) { px.syncs = true; px.hs = n0 & 1; px.vs = n0 >> 1 & 1; }

    void control(unsigned s0, unsigned s1, unsigned s2);
    void island(unsigned s0, unsigned s1, unsigned s2);
    void step(unsigned s0, unsigned s1, unsigned s2) {
        pixel++;
        px = Pixel{};
        if (st == CTRL) control(s0, s1, s2);
        else if (st == VGUARD || st == VIDEO) {
            const bool guard = s0 == GB_A && s1 == GB_B && s2 == GB_A;
            if (st == VGUARD && guard && ++guard_n <= 2) return;
            if (st == VGUARD && guard_n != 2) error("video guard band of " + std::to_string(guard_n));
            if (ctrl(s0) >= 0) { st = CTRL; control(s0, s1, s2); return; }
            st = VIDEO;
            px.video = true;
            px.rgb = video(s2) << 16 | video(s1) << 8 | video(s0);
        } else island(s0, s1, s2);
    }
};

inline void HdmiSink::control(unsigned s0, unsigned s1, unsigned s2) {
    const int c0 = ctrl(s0), c1 = ctrl(s1), c2 = ctrl(s2);
    if (c0 >= 0 && c1 >= 0 && c2 >= 0) {
        syncs(c0);
        const int kind = (c1 == 1 && c2 == 0) ? 1 : (c1 == 1 && c2 == 1) ? 2 : 0;
        pre_n = (kind && kind == pre_kind) ? pre_n + 1 : kind ? 1 : 0;
        pre_kind = kind;
        return;
    }
    const bool vg = s0 == GB_A && s1 == GB_B && s2 == GB_A, dg = dguard(s0, s1, s2);
    if ((vg && pre_kind != 1) || (dg && pre_kind != 2) || (!vg && !dg)) error("no preamble/guard before a period");
    else if (pre_n != 8) error("preamble of " + std::to_string(pre_n) + " pixels");
    if (dg) syncs(terc4(s0));
    st = vg ? VGUARD : DGUARD_L;
    guard_n = 1;
    k = 0;
    packets_in_island = 0;
    pre_n = pre_kind = 0;
}

inline void HdmiSink::island(unsigned s0, unsigned s1, unsigned s2) {
    const bool guard = dguard(s0, s1, s2);
    const int n0 = terc4(s0), n1 = terc4(s1), n2 = terc4(s2);
    if (st == DGUARD_L && guard) { syncs(n0); if (++guard_n > 2) error("leading guard band > 2"); return; }
    if (st == DGUARD_L && guard_n != 2) error("leading guard band of " + std::to_string(guard_n));
    if (st == DGUARD_T) {
        if (guard) { syncs(n0); guard_n++; return; }
        if (guard_n != 2) error("trailing guard band of " + std::to_string(guard_n));
        st = CTRL;
        control(s0, s1, s2);
        return;
    }
    if (guard) {
        if (k != 0) error("island ends inside a packet");
        if (packets_in_island == 0 || packets_in_island > 18) error("island of " + std::to_string(packets_in_island) + " packets");
        st = DGUARD_T;
        guard_n = 1;
        syncs(n0);
        return;
    }
    st = DATA;
    if (n0 < 0 || n1 < 0 || n2 < 0) { error("not TERC4 inside an island"); return; }
    syncs(n0);
    packet_pixel(n0, n1, n2);
}
