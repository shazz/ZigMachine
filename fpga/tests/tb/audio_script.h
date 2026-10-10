// The audio stimulus script, as tests/audio_ref/audio_ref.zig reads it (its
// header has the commands), turned into register writes on zm_audio_core's bus
// (docs/FPGA_AUDIO.md has the map). One `Cmd` per line; `run` is the only one
// that lets samples be made, so every write lands between two samples, as the
// machine's players do it.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

struct Cmd {
    long run = 0;                                   // > 0: make this many samples
    bool mid = false;                               // the writes land while the next sample is mixed
    std::vector<std::pair<unsigned, uint32_t>> wr;  // else these bus writes, in order
};

struct Script {
    std::vector<Cmd> cmds;
    std::vector<uint8_t> pcm;  // the memory the PCM channels read

    static std::vector<uint8_t> load(const std::string &path) {
        std::ifstream f(path, std::ios::binary);
        if (!f) std::fprintf(stderr, "cannot read %s\n", path.c_str()), std::exit(2);
        return {std::istreambuf_iterator<char>(f), {}};
    }
    static unsigned ch(long c, unsigned field) { return 0x100 + 0x40 * unsigned(c) + 4 * field; }

    void line(const std::string &raw) {
        std::string text = raw.substr(0, raw.find('#'));
        std::istringstream in(text);
        std::string op;
        if (!(in >> op)) return;
        if (op == "mid") {  // the command after it, made while one sample is mixed
            line(text.substr(text.find("mid") + 3));
            cmds.back().mid = true;
            return;
        }
        Cmd c;
        long a = 0, b = 0;
        static const std::vector<std::string> fields = {"", "", "", "", "step", "vol", "pan", "pos"};
        if (op == "pcm") { std::string p; in >> p; pcm = load(p); return; }
        if (op == "run") in >> c.run;
        else if (op == "ym") in >> a >> b, c.wr.push_back({4 * unsigned(a), uint32_t(b)});
        else if (op == "pk") in >> a >> b, c.wr.push_back({0x080 + 4 * unsigned(a), uint32_t(b)});
        else if (op == "pkclock") in >> a, c.wr.push_back({0x0C0, a ? 1u : 0u});
        else if (op == "reset") c.wr.push_back({0x040, 1});
        else if (op == "act") in >> a >> b, c.wr.push_back({ch(a, 8), b ? 1u : 0u});
        else if (op == "trig") trigger(in, c);
        else {
            unsigned f = 0;
            for (unsigned i = 4; i < fields.size(); i++) if (op == fields[i]) f = i;
            if (!f) std::fprintf(stderr, "script: %s\n", raw.c_str()), std::exit(2);
            in >> a >> b;
            c.wr.push_back({ch(a, f), uint32_t(b)});
        }
        cmds.push_back(c);
    }
    // machinePaulaTrigger: the staged fields and the pan, then TRIGGER.
    static void trigger(std::istringstream &in, Cmd &c) {
        long n, data, len, ls, ll, pan;
        in >> n >> data >> len >> ls >> ll >> pan;
        const long v[4] = {data, len, ls, ll};
        for (unsigned f = 0; f < 4; f++) c.wr.push_back({ch(n, f), uint32_t(v[f])});
        c.wr.push_back({ch(n, 6), uint32_t(pan)});
        c.wr.push_back({ch(n, 8), 2});
    }
    explicit Script(const std::string &path) {
        std::ifstream f(path);
        if (!f) std::fprintf(stderr, "cannot read %s\n", path.c_str()), std::exit(2);
        for (std::string l; std::getline(f, l);) line(l);
    }
};
