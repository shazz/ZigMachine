// A C++ model of a monitor's DDC EEPROM (a 24C02 at I2C address 0x50) and a
// checker of the I2C standard-mode timing, for tests/tb/edid_core_tb.cpp. Both
// see the bus once a 40 MHz clock (25 ns): `scl`/`sda` are the wired-AND of the
// master's and the slave's drives with the pull-ups.
//
// The slave drives SDA HOLD clocks after SCL falls (tHD;DAT), ACKs its address
// and every byte written, reads sequentially from the word pointer, and stops
// sending at the master's NACK. Fault knobs: `present` (false: never ACKs),
// `stretch` (holds SCL low that long after every ACK), `stuck` (starts
// mid-byte, sending zeros, as after a master reset), `scl_stuck` (SCL low
// forever).
#pragma once
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

struct DdcSlave {
    std::vector<uint8_t> mem = std::vector<uint8_t>(256, 0);
    bool present = true, stuck = false, scl_stuck = false;
    int stretch = 0;
    bool sda_low = false, scl_low = false;  // the slave's drives
    int starts = 0, stops = 0, bytes_sent = 0;
    std::vector<std::string> errors;

    static constexpr int HOLD = 12;
    enum St { IDLE, RECV, ACK, SEND, MACK } st = IDLE;
    bool addr_phase = false, reading = false, master_ack = false;
    int bits = 0, pend = 0, stretch_left = 0;
    bool pend_val = false, prev_scl = true, prev_sda = true;
    uint8_t sh = 0, ptr = 0;

    void begin() {
        if (stuck) { st = SEND; sh = 0x00; bits = 4; sda_low = true; }
        scl_low = scl_stuck;
    }
    void drive(bool low) { pend = HOLD; pend_val = low; }
    void send_bit() { drive(!((sh >> (7 - bits)) & 1)); }
    void load() { sh = mem[ptr++]; bits = 0; st = SEND; bytes_sent++; send_bit(); }

    void byte_in() {
        if (addr_phase && (sh >> 1) != 0x50) { st = IDLE; return; }  // another device: stay quiet
        if (addr_phase && !present) { st = IDLE; return; }
        if (addr_phase) reading = sh & 1; else ptr = sh;
        addr_phase = false;
        st = ACK;
        drive(true);
        if (stretch) { scl_low = true; stretch_left = stretch; }
    }

    void on_fall() {
        switch (st) {
            case RECV: if (bits == 8) byte_in(); break;
            case ACK: if (reading) load(); else { st = RECV; bits = 0; sh = 0; drive(false); } break;
            case SEND:
                if (++bits == 8) { st = MACK; drive(false); } else send_bit();
                break;
            case MACK: if (master_ack) load(); else st = IDLE; break;
            default: break;
        }
    }

    void tick(bool scl, bool sda) {
        if (pend && --pend == 0) sda_low = pend_val;
        if (stretch_left && --stretch_left == 0) scl_low = false;
        if (scl_stuck) scl_low = true;
        if (scl && prev_scl && sda != prev_sda) {
            if (!sda) { starts++; st = RECV; addr_phase = true; bits = 0; sh = 0; }
            else { stops++; st = IDLE; }
            if (st == IDLE || st == RECV) { sda_low = false; pend = 0; }
        } else if (scl && !prev_scl) {
            if (st == RECV) { sh = uint8_t(sh << 1 | sda); bits++; }
            if (st == MACK) master_ack = !sda;
        } else if (!scl && prev_scl) {
            on_fall();
        }
        prev_scl = scl;
        prev_sda = sda;
    }
};

// Standard-mode minimums (I2C UM10204 table 10), in 25 ns clocks.
struct I2cTiming {
    static constexpr long T_LOW = 188, T_HIGH = 160, T_SU_STA = 188, T_HD_STA = 160, T_SU_STO = 160, T_BUF = 188,
                          T_SU_DAT = 10;
    long now = 0, scl_rise = -1000000, scl_fall = -1000000, sda_edge = -1000000, start = -1000000,
         stop = -1000000;
    bool prev_scl = true, prev_sda = true, seen_fall = false;
    std::vector<std::string> errors;

    void fail(const char *what, long got, long want) {
        char b[128];
        std::snprintf(b, sizeof b, "%s %ld clocks < %ld at clock %ld", what, got, want, now);
        if (errors.size() < 8) errors.push_back(b);
    }
    void tick(bool scl, bool sda) {
        now++;
        if (scl && prev_scl && sda != prev_sda) {
            if (!sda) {  // START (or repeated START)
                if (now - scl_rise < T_SU_STA && seen_fall) fail("tSU;STA", now - scl_rise, T_SU_STA);
                if (now - stop < T_BUF) fail("tBUF", now - stop, T_BUF);
                start = now;
            } else {     // STOP
                if (now - scl_rise < T_SU_STO) fail("tSU;STO", now - scl_rise, T_SU_STO);
                stop = now;
            }
        }
        if (!scl && sda != prev_sda) sda_edge = now;
        if (scl && !prev_scl) {
            if (seen_fall && now - scl_fall < T_LOW) fail("tLOW", now - scl_fall, T_LOW);
            if (now - sda_edge < T_SU_DAT) fail("tSU;DAT", now - sda_edge, T_SU_DAT);
            scl_rise = now;
        }
        if (!scl && prev_scl) {
            if (now - scl_rise < T_HIGH) fail("tHIGH", now - scl_rise, T_HIGH);
            if (start > scl_rise && now - start < T_HD_STA) fail("tHD;STA", now - start, T_HD_STA);
            scl_fall = now;
            seen_fall = true;
        }
        prev_scl = scl;
        prev_sda = sda;
    }
};
