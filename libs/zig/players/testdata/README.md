# Test fixtures for the players' native tests

| File | What | Source | Licence |
|---|---|---|---|
| `beat_dis_head.bin` | `beat_dis.sndh`'s first 0x64 + 0x125A bytes: the header, the code and the tables, no samples (`digi_test.zig`) | `docs/music/union/beat_dis.sndh` | as the SNDH collection |
| `monty.sndh` | Mad Max's "Auf Weidersehen Monty - digidrums", whole (18,376 bytes): its driver, song and drums (`digi_monty_test.zig`) | `docs/music/auf_weidersehen_monty_digi.sndh` | as the SNDH collection |
| `cpu6502_sst.bin` | 14,160 single-instruction 6502 tests: the first 60 of each of the 236 opcodes `cpu6502.zig` runs (the 12 JAMs and 8 unstable opcodes left out), with registers, the RAM touched, the cycle count and the bus writes (`cpu6502_test.zig`) | [SingleStepTests/65x02](https://github.com/SingleStepTests/65x02) `6502/v1/`, commit `2f6980a2d95757486c7bee24355c360e40e2a224` (2025-05-10), baked by `prototypes/sap_re/sst_fetch.py --per 60` (layout in its docstring) | MIT |
| `big_handler.bin` | `digital/Ace_2.sndh` bytes 0x1938..0x2224: Mad Max's 3-voice mixer handler as the file holds it (its tail still the `bclr`, its addresses unrelocated) and its 256-entry volume table (`digi_big_test.zig`) | `docs/music/digital/Ace_2.sndh` | as the SNDH collection |
| `mix4_handler.bin` | `union/thalion_forever.sndh` bytes 0x54C..0xBBC: Hippel's 4-voice mixer handler, its volume table, its voices and their loop words (`digi_mix4_test.zig`) | `docs/music/union/thalion_forever.sndh` | as the SNDH collection |
