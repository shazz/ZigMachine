// Checks of the packets tests/tb/hdmi_decode.h rebuilds, for
// tests/tb/hdmi_audio_tb.cpp, from HDMI 1.3a section 5.3 and CEA-861-D:
//   Audio Sample (0x02): the samples (16-bit L-PCM, left-justified in 24), the
//     IEC 60958 bits (V = U = 0, even parity P, C = the channel status the
//     source must send, B on frame 0 of 192) counted independently here;
//   ACR (0x01): N in all four subpackets, every CTS the floor or the ceiling of
//     f_TMDS x N / (128 fs) (6144 / 40000 at 48 kHz, 6272 / 44444.4 at 44.1 kHz
//     on 40 MHz), and their running sum within one clock of the ideal: the
//     average CTS is exact (the first, measured from reset, is not counted);
//   AVI (0x82) and Audio (0x84) InfoFrames: version, length, checksum, fields;
//   null (0x00); any other type is an error.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>
#include "hdmi_decode.h"

struct PacketCheck {
    std::vector<std::pair<int16_t, int16_t>> samples;
    std::vector<std::string> errors;
    int avi = 0, aif = 0, acr = 0, null = 0, asp = 0;
    unsigned frame = 0;  // IEC 60958 frame of the next sample
    // The stream's rate: 48 kHz by default (set by the testbench).
    unsigned fs = 48000, n_acr = 6144;
    double f_tmds = 40e6;
    std::vector<unsigned> cts;  // every CTS received, in order
    long double cts_sum = 0;    // ... from the second on
    double cts_worst = 0;       // the running sum's worst distance from the ideal, in clocks

    double cts_ideal() const { return f_tmds * n_acr / (128.0 * fs); }

    void error(const std::string &e) { if (errors.size() < 20) errors.push_back(e); }

    // IEC 60958-3 consumer: bit 2 (no copyright), bits 24..27 the rate (0100 =
    // 48 kHz, 0000 = 44.1 kHz), bits 32..35 the word length (0100 = 16 bits),
    // bits 20/21 the channel number (1 left, 2 right).
    bool channel_status(unsigned f, bool right) const {
        return f == 2 || (fs == 48000 && f == 25) || f == 33 || f == (right ? 21u : 20u);
    }
    static unsigned parity(uint32_t v) { unsigned p = 0; while (v) { p ^= v & 1; v >>= 1; } return p; }

    void sample(const uint8_t *sb, bool b_flag) {
        const uint32_t l = sb[0] | sb[1] << 8 | sb[2] << 16, r = sb[3] | sb[4] << 8 | sb[5] << 16;
        const unsigned f = frame % 192, x = sb[6];
        const unsigned vl = x & 1, ul = x >> 1 & 1, cl = x >> 2 & 1, pl = x >> 3 & 1;
        const unsigned vr = x >> 4 & 1, ur = x >> 5 & 1, cr = x >> 6 & 1, pr = x >> 7 & 1;
        if (vl || ul || vr || ur) error("V or U set");
        if (cl != channel_status(f, false) || cr != channel_status(f, true)) error("channel status bit " + std::to_string(f));
        if (pl != (parity(l) ^ cl) || pr != (parity(r) ^ cr)) error("parity at frame " + std::to_string(frame));
        if (b_flag != (f == 0)) error("B flag at frame " + std::to_string(frame));
        if ((l & 0xFF) || (r & 0xFF)) error("16-bit sample not left-justified");
        samples.emplace_back(int16_t(l >> 8), int16_t(r >> 8));
        frame++;
    }

    void on_audio(const Packet &p) {
        const unsigned present = p.hb[1] & 15, b = p.hb[2] >> 4;
        if (p.hb[1] & 0xF0 || p.hb[2] & 15) error("audio sample header: layout/flat bits set");
        if (present != 1 && present != 3 && present != 7 && present != 15) error("samples not packed from 0");
        for (int j = 0; j < 4; j++)
            if (present >> j & 1) sample(p.sb[j], b >> j & 1);
            else if (b >> j & 1) error("B flag on an absent sample");
        asp++;
    }

    void on_acr(const Packet &p) {
        for (int i = 0; i < 4; i++) {
            const uint8_t *s = p.sb[i];
            const unsigned cts = (s[1] & 15) << 16 | s[2] << 8 | s[3], n = (s[4] & 15) << 16 | s[5] << 8 | s[6];
            if (s[0] || n != n_acr || std::fabs(cts - cts_ideal()) >= 1.0)
                error("ACR N " + std::to_string(n) + " CTS " + std::to_string(cts));
            if (i && cts != this->cts.back()) error("ACR subpackets differ");
            if (!i) this->cts.push_back(cts);
        }
        if (acr++ == 0) return;
        cts_sum += this->cts.back();
        cts_worst = std::max(cts_worst, double(std::fabs(cts_sum - (long double)acr_counted() * cts_ideal())));
        if (cts_worst >= 1.0) error("the CTS sum drifts from the ideal: " + std::to_string(cts_worst));
    }

    // An InfoFrame's PB0..PB27 (7 a subpacket), checked against its header.
    std::vector<uint8_t> infoframe(const Packet &p, unsigned version, unsigned length) {
        std::vector<uint8_t> pb;
        unsigned sum = p.hb[0] + p.hb[1] + p.hb[2];
        for (int i = 0; i < 4; i++) for (int b = 0; b < 7; b++) { pb.push_back(p.sb[i][b]); sum += p.sb[i][b]; }
        if (p.hb[1] != version || p.hb[2] != length) error("InfoFrame version/length");
        if (sum & 0xFF) error("InfoFrame checksum");
        return pb;
    }

    long acr_counted() const { return long(cts.size()) - 1; }

    void take(const Packet &p) {
        switch (p.hb[0]) {
            case 0x00: null++; break;
            case 0x01: on_acr(p); break;
            case 0x02: on_audio(p); break;
            case 0x82: {
                const auto pb = infoframe(p, 2, 13);
                if (pb[1] >> 5 & 3) error("AVI: not RGB");
                if ((pb[3] >> 2 & 3) != 2) error("AVI: not full-range RGB");
                if (pb[4] != 0) error("AVI: a VIC for 800x600");
                avi++;
                break;
            }
            case 0x84: {
                const auto pb = infoframe(p, 1, 10);
                if ((pb[1] & 7) != 1) error("Audio InfoFrame: not 2 channels");
                aif++;
                break;
            }
            default: error("packet type " + std::to_string(p.hb[0]));
        }
    }
};
