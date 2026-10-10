// zm_pokey (Verilator) against libs/zig/players/pokey.zig: plays a register-write
// script (tests/pokey_scripts.py) into the RTL and compares the four channel
// levels with the oracle's trace (tests/pokey_ref) after EVERY machine cycle.
// Bit-exact or it fails at the first differing cycle.
//
//   pokey_tb <script> <trace>
//
// A write goes in on a clock where `cen` is low (between machine cycles, as the
// model's write() lands); the levels are read one clock after each `cen` clock
// (they are registered). `mix` must be the sum of the four levels.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "Vzm_pokey.h"
#include "verilated.h"

static Vzm_pokey* d;
static unsigned long long clocks = 0;

static void tick() {
    d->clk = 0;
    d->eval();
    d->clk = 1;
    d->eval();
    clocks++;
}

static void write(unsigned addr, unsigned data) {
    if (d->cen) {  // ticking on would run a machine cycle the model does not
        printf("FAIL: more writes between two machine cycles than the enable leaves clocks for\n");
        exit(1);
    }
    d->we = 1;
    d->addr = addr & 0xF;
    d->din = data & 0xFF;
    tick();
    d->we = 0;
}

static void cycle() {
    for (;;) {
        bool c = d->cen;
        tick();
        if (c) break;
    }
    tick();  // the registered levels catch up
}

static std::vector<unsigned char> slurp(const char* path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) { fprintf(stderr, "cannot read %s\n", path); exit(2); }
    return std::vector<unsigned char>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

int main(int argc, char** argv) {
    if (argc < 3) { fprintf(stderr, "usage: pokey_tb <script> <trace>\n"); return 2; }
    std::ifstream script(argv[1]);
    std::vector<unsigned char> trace = slurp(argv[2]);
    d = new Vzm_pokey;
    d->rst = 1;
    tick();
    tick();
    d->rst = 0;
    unsigned long long n = 0, writes = 0, changes[4] = {0, 0, 0, 0};
    unsigned prev = 0;
    std::string line;
    while (std::getline(script, line)) {
        line = line.substr(0, line.find('#'));
        std::istringstream in(line);
        std::string op;
        if (!(in >> op)) continue;
        if (op == "w") {
            unsigned a, v;
            in >> std::hex >> a >> v;  // the scripts write 0x.. hex
            write(a, v);
            writes++;
            continue;
        }
        unsigned long long k;
        in >> k;
        for (; k; k--, n++) {
            cycle();
            if (2 * n + 1 >= trace.size()) { printf("FAIL: the trace ends at cycle %llu\n", n); return 1; }
            unsigned want = trace[2 * n] | trace[2 * n + 1] << 8, got = d->level;
            unsigned sum = (got & 15) + (got >> 4 & 15) + (got >> 8 & 15) + (got >> 12);
            if (got != want || d->mix != sum) {
                printf("FAIL at machine cycle %llu (%llu writes in): rtl %04x mix %u, zig %04x\n", n, writes, got,
                       (unsigned)d->mix, want);
                return 1;
            }
            for (int c = 0; c < 4; c++) changes[c] += ((got ^ prev) >> (4 * c) & 15) != 0;
            prev = got;
        }
    }
    if (2 * n != trace.size()) { printf("FAIL: %llu cycles run, the trace has %zu\n", n, trace.size() / 2); return 1; }
    printf("pokey: %llu machine cycles bit-exact (%llu clocks, %llu writes); level changes %llu %llu %llu %llu\n", n,
           clocks, writes, changes[0], changes[1], changes[2], changes[3]);
    delete d;
    return 0;
}
