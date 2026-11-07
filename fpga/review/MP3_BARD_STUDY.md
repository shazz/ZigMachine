# MP3 on BARD: feasibility study (6 Nov 2026)

Matt: "start with helix, but do a web search to see if nobody wrote a fast decoder recently". This is a
study only. No player goes into the system image yet.

**Answer: it fits easily.** Two fixed-point decoders were measured on BARD's board core
(`SndNdD16Dyn8Sx`, combo16) in the sim. Both decode 44.1 kHz stereo at about **35 % of BARD**, and both
are bit-exact with their host builds. Both are within 1-2 LSB of ffmpeg's float decoder (SNR 78-87 dB).
Neither needs any optimisation. They tie on cost and accuracy, so the choice comes down to two things,
both Matt's to decide:
- the **licence**: Helix is RPSL, pvmp3 is Apache-2.0;
- the **output path**: CHORUS's PCM channels are 8-bit. See "Output", below.

## 1. Candidates (web research, 6 Nov)

| # | Decoder | Licence | Math | Published cost (44.1k stereo) | Size | Upkeep | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | **pvmp3** (PacketVideo / OpenCORE, in AOSP `frameworks/av/media/module/codecs/mp3dec`) | **Apache-2.0** (NOTICE + patent disclaimer) | fixed point; portable C path `pv_mp3dec_fxd_op_c_equivalent.h`; ARM asm optional | none published | measured: 48 KB code + tables, 27.8 KB state | maintained in AOSP (fuzzer, tests) | **measured: 34 % of BARD** |
| 2 | **Helix MP3** (RealNetworks; chmorgan/libhelix-mp3, ultraembedded RISC-V port, ESP8266Audio, arduino-libhelix) | **RPSL 1.0** (or RCSL); every copy checked carries RPSL | fixed point; 32x32->64 through `mulh` on RISC-V | 26 MHz on ARM7TDMI (RealNetworks' table, zero-wait memory) | measured: 45 KB code + tables, 23.8 KB state | dormant upstream; forks are small | **measured: 35 % of BARD** |
| 3 | Lefucjusz/Helix-MP3-Decoder | repo says GPL-3.0, but the code is Helix's RPSL (the relabel is dubious) | as Helix | none ("real time on Pico 2 RISC-V") | as Helix | 5 commits | its RISC-V `assembly.h` is the same `mulh` MULSHIFT32 as chmorgan's (diffed): no gain to expect |
| 4 | libmad | GPL-2 | fixed point | RP2350 (M33) ~23 MHz, RP2040 (M0+) ~42 MHz (earlephilhower BackgroundAudio SpeedTest); ARM9 ~31 MHz | n/a | dead since 2004 | GPL-2 would cover all of system.rv32 |
| 5 | FFmpeg `mpegaudiodec_fixed` | LGPL-2.1+ | fixed point | none for embedded; a 2006 ARM thread found it slower than libmad | large (needs avcodec) | active | LGPL static linking needs relinkable objects |
| 6 | Espressif `esp_audio_codec` | Espressif's licence; ships as a binary `.a` for Xtensa/RISC-V (UNVERIFIED) | n/a | no C3 figures | n/a | active (v2.4.1) | binary only: unusable |
| 7 | minimp3 (CC0), nanomp3 (Rust c2rust of it), rmp3 | CC0 | **float** | n/a | n/a | n/a | no integer fork found (minimp3 issue #110: the user moved to Helix) |
| 8 | puremp3, symphonia (Rust) | MIT/Apache, MPL-2.0 | float | n/a | n/a | n/a | float: no |

Not found:
- any MHz-per-stream figure for a RISC-V MP3 decoder (ESP32-C3, CH32V, K210, BL602);
- a licence or benchmark for "picomp3lib" (Helix-derived).

A 2004 paper on a MIPS-like RISC32 core gives 48 MIPS and 49 KB for 128k/44.1k joint stereo. It is a
different ISA, so it is a rough guide only.

**Licences, for firmware statically linked into a downloadable system image:**
- **Apache-2.0** (pvmp3): ship the licence and NOTICE, and mark the files we modify. It carries a patent
  grant and no source obligation, and it mixes with anything.
- **RPSL 1.0** (Helix): OSI-approved, but GPL-incompatible.
  - A binary distribution must carry a notice saying where the source is (§2.1(e)).
  - The source of our *modifications* must be public for as long as we ship, or 12 months (§2.1(d)).
  - A distributed derivative work is RPSL as a whole (§4.1). Mere aggregation (§4.3) and separate modules
    under a compatible licence (§4.2) are exempt, so the decoder must stay a separate module, and it can
    never join GPL code.
- **GPL-2** (libmad): system.rv32 would have to be GPL-2, with its complete source offered.
- **LGPL**: static linking requires users to be able to relink against a modified library.

Sources:
- Helix: https://github.com/chmorgan/libhelix-mp3 (LICENSE.txt, RPSL.txt), https://github.com/ultraembedded/libhelix-mp3,
  https://github.com/Lefucjusz/Helix-MP3-Decoder
- RPSL: https://opensource.org/license/rpsl-1-0, https://raw.githubusercontent.com/earlephilhower/ESP8266Audio/master/src/libhelix-mp3/RPSL.txt,
  https://lwn.net/Articles/43130/
- Helix cost table: https://applied-ee.github.io/embedded/docs/audio-projects/audio-formats/audio-compression-codecs/,
  https://www.microchip.com/en-us/software-library/helix-mp3-decoder-library, https://www.silabs.com/documents/public/application-notes/an1112-efm32-helix-mp3-decoder.pdf
- libmad and Helix MHz: https://lists.mplayerhq.hu/pipermail/mplayer-dev-eng/2006-August/045211.html,
  https://github.com/earlephilhower/BackgroundAudio
- pvmp3: https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/media/module/codecs/mp3dec/
- minimp3: https://github.com/lieff/minimp3 (issue #110). Rust: https://docs.rs/puremp3, https://docs.rs/crate/rmp3/latest
- Espressif: https://components.espressif.com/components/espressif/esp_audio_codec

## 2. Measured on BARD

**Setup:**
- `make snd-cbench` with the bench in `cycles/sound/mp3bench.c` and an adapter per decoder:
  `mp3a_helix.c`, `mp3a_pv.c` (+ `mp3a_pv_shim.h`).
- Built `-march=rv32i_zmmul -O2`, as all of BARD's firmware is. The image's DIV/REM guard passed.
- The model is `soc.hp_sim --sound-cpu --sound-core VexRiscv_SndNdD16Dyn8Sx.v`, the combo16 core
  (`vexgen/gen.sh SndNdD16Dyn8Sx:16384:2:16384:2:snd,nodiv,dynpred,h8,shex`, md5 bb06b0c7). It was built and
  run on the laptop (omarchy, `~/mp3bard/zm`, from this branch's fpga/).
- Each run took 90-100 s: 4 streams x 8 MP3 frames.

**Streams:** all synthesised by `tools/mp3_bard_streams.sh`, so they are CC0. The signal is saw-wave chords,
an arpeggio and noise hits. LAME (ffmpeg libmp3lame) encodes them with no ID3 tag and no Xing frame:
- `s44_128`: 44.1 kHz stereo 128k
- `s32_128`: 32 kHz stereo 128k
- `m44_64`: 44.1 kHz mono 64k
- `s44_320`: pink noise at 320k stereo, the dense-Huffman worst case

**Units:**
- An MP3 frame is 1152 samples: 26.1 ms (1.567 video frames) at 44.1 kHz, 36 ms at 32 kHz.
- "% of BARD" is cycles x rate / (1152 x 100 MHz): the decoder's average share of BARD in real time.
- The figures are the mean of frames 1-7 (frame 0, cold, dropped); the peak is over all 8 frames.

| Stream | Helix Mc / MP3 frame | Helix % of BARD (peak) | pvmp3 Mc / MP3 frame | pvmp3 % of BARD (peak) |
|---|---|---|---|---|
| **44.1 kHz stereo 128k** | 0.910 | **34.8 % (36.3)** | 0.890 | **34.0 % (35.9)** |
| 32 kHz stereo 128k | 0.939 | 26.0 % (26.8) | 0.907 | 25.1 % (27.1) |
| 44.1 kHz mono 64k | 0.433 | 16.6 % (17.1) | 0.318 | 12.1 % (14.3) |
| 44.1 kHz stereo 320k (noise) | 0.970 | 37.1 % (37.9) | 0.750 | 28.6 % (31.5) |

- **In BARD's 60 Hz units** (the BRAM/CPI studies' rows): 44.1 kHz stereo averages 0.58 Mc a video frame
  for Helix and 0.57 for pvmp3, of 1.67.
- **One MP3 frame decodes in one go, though.** The 60 Hz tick that decodes it pays 0.91-0.99 Mc, which is
  55-59 % of that tick. An output cushion of two MP3 frames lets the player decode when there is room.
- **Soft divides** (the core has no divider; the bench's counting `__divsi3` family replaces libgcc's):
  Helix makes 14 a frame (8 in mono), pvmp3 makes 4, including the bench's frame-length parse.
  At under 0.5 % of the cycles they do not matter.
- **Bus waits a frame** (I-bus / D-bus): Helix ~23 k / ~167 k (18 % of its cycles), pvmp3 ~21 k / ~117 k
  (13 %). D-bus waits are the only visible lever if one is ever needed.

**Accuracy.** Each host twin (`tools/mp3_bard_host.c`, the same adapter and sources) decodes the whole file.
Every frame BARD decoded has the host's PCM hash: **bit-exact** (`tools/mp3_bard_check.py`).

Against ffmpeg's float decoder (`tools/mp3_bard_snr.py`, alignment lag 0 on every stream):

| Stream | Helix | pvmp3 |
|---|---|---|
| 44.1 stereo 128k | SNR 86.7 dB, max 1 LSB, rms 0.23 | 83.1 dB, max 2 LSB, rms 0.35 |
| 32 stereo 128k | 86.5 dB, max 1 | 83.3 dB, max 2 |
| 44.1 mono 64k | 86.3 dB, max 1 | 82.8 dB, max 2 |
| 44.1 stereo 320k | 79.4 dB, max 1 | 78.1 dB, max 2 |

Both are at the 16-bit rounding floor.

**Memory:**

| | Code + tables | State (heap) |
|---|---|---|
| Helix | 45.1 KB (tables 12.4 KB) | 23.8 KB (subband 8.7, IMDCT 6.9, Huffman 4.6 KB) |
| pvmp3 | 48.2 KB (tables 9.5 KB) | 27.8 KB |

Both are trivial against BARD's 2 MiB image and 3 MiB heap. pvmp3 is C++, but it pulls in no C++ runtime:
no `__cxa`/`_Unwind`/vtables, and no `.init_array` or `.eh_frame` in the image. A production build should
still pass `-fno-exceptions -fno-rtti`.

**pvmp3 wants whole frames.** Its `validate_input` refuses a buffer that ends in a partial frame. The
adapter therefore frames the input from the header (`mp3_frame_len`, in `mp3bench.h`), as a streaming
player must do with its ring anyway.

No cheap wins were tried: both are far below the ~70 % bar.

## 3. Design sketch: a jukebox cart

**Input.** The cart (ZIGGY) reads the .mp3 from C: through KOS GEMDOS (`Fopen`/`Fread`, ~0.5 ms a request,
up to 32 KB).
- 128 kbps is 16 KB/s, so one 32 KB `Fread` every 2 s; 320 kbps needs one every 0.8 s.
- The cart keeps a 64 KB input ring in its own memory (two halves, refilled a half at a time).
- It feeds BARD the way ST Replay's F10 feeds the PCM stream today: `zg.audioStreamStart` / `audioFeed` /
  `audioStreamStop` become effects `0x81..0x83`. BARD copies a feed's bytes from the cart's memory in DDR
  while ZIGGY waits for the ACK (`host/audio_bridge.c` `audio_stream_feed`, `host/audio_pcm.c`).

**Decoder.** BARD keeps its own compressed ring, ~16 KB: one second at 128k, longer than the bit
reservoir's 511 bytes. It decodes a frame whenever the output ring has room for 1152 more samples. The
decoder belongs on the native player path in `host/audio.c` (C linked into snd.elf, as here), not in
wasm2c'd demo-audio.wasm.

**New ABI.** A new mailbox op or effect kind: "compressed stream start (format = MP3) / feed / stop", plus
a status word back (the ring's fill, decode errors, rate and channels) so the cart knows when to `Fread`.
`requestSongBytes(kind mp3)` would also work for a short file held whole in song RAM, but a 3-minute
128k track is 2.9 MB, so streaming is the general case.

**Output: the real decision.** CHORUS's PCM channels play **8-bit signed** samples
(`rtl/audio/zm_audio_pcm.v`: `s8 x VOL x pan`, VOL 0..256). Three ways:
- **(a) 8-bit, no RTL.** Two Paula channels, hard left and right, each on a ring like the XM mixer's
  (16 KiB a channel), the decode truncated or dithered to 8 bits. That is ~48 dB SNR, which throws away
  the decoder's 80+ dB.
- **(b) 16-bit from two channel pairs, no RTL.** A side's hi byte at VOL 256 plus its lo byte at VOL 1
  sums exactly to 256 x hi + lo. The accumulators are 28-bit and exact (the module's own comment), so
  that is a true 16-bit sample. It takes all four Paula channels, so nothing is left for SFX while MP3
  plays, and it doubles the PCM port's reads.
  - **Check in the sim first:** whether CHORUS's mix → DAC path keeps those low bits.
- **(c) A 16-bit PCM mode in CHORUS.** RTL plus a HW API version bump, a new break test, and
  browser = RTL parity in machine-audio.wasm.

BARD's cost for (a) or (b) is a few cycles a sample on top of the decode. That is ~0.5 %.

**Option (b), checked (6 Nov, after Matt chose pvmp3).** `fpga/tests/hilo_probe.py` plays 6000 stereo
samples, among them the extremes, through the RTL core bench (CXXRTL `zm_audio_core`) and through the
Zig engine (`tests/audio_ref`, the browser's machine-audio). Each side is a high byte at VOL 256 plus a
low byte, both channels hard-panned.

| Low byte | out == x (16-bit) | out == floor(x / 2) |
|---|---|---|
| VOL 1 (256 hi + lo = x) | 0 / 6000 | 5993 / 6000 (x >= 32640 has no hi byte) |
| VOL 2 (128 hi + lo = x >> 1) | 0 / 6000 | **6000 / 6000**, on the RTL and the Zig engine alike |

**So (b) is exact, but to 15 bits at -6 dB, not 16.** A Paula channel's gain is
`0.5 x VOL/256 x pan`: one channel at VOL 256 and hard pan reaches only half of full scale, and
`to16()` floors the bus at 2^-8 of the units a VOL-1 byte lands on. The best two channels a side can do
is `x >> 1`: 15 bits, about 90 dB, deterministic. A true 16-bit out needs option (c), a 16-bit CHORUS
PCM mode (RTL, Matt's go).

**48 kHz files.** CHORUS runs at 44.1 kHz. A 48 kHz MP3, like Matt's test track, needs BARD to resample
in software (a linear pass is a few cycles a sample). The alternative, a fractional Paula STEP (71331),
is nearest-sample resampling: it aliases, and it is no longer bit-exact against a host decode.

**Licence.** pvmp3 (Apache-2.0) needs only NOTICE text in the SDK's THIRD_PARTY.md. Helix (RPSL) needs:
- a source notice;
- our modifications published for as long as we ship;
- the decoder kept a separate module, never mixed with GPL code (zeST's GPL-3 sits on the same card,
  but that is aggregation).

## Recommendation

1. MP3 is feasible on today's BARD core, with ~65 % of BARD left at 44.1 kHz stereo. That is enough for a
   jukebox, and even for MP3 under a light player.
2. Helix and pvmp3 tie on cost (34.8 vs 34.0 %) and accuracy (1 vs 2 LSB from ffmpeg). Matt asked to start
   with Helix and it is measured; **pvmp3 is the safer pick for a system image others download** (Apache-2.0
   vs RPSL's source-publication terms).
3. **For Matt:** the licence (pvmp3 or Helix), and the output path ((b), no RTL, after a sim check of the
   low bits; or (c), a 16-bit PCM mode). After that, a player row: the stream op, BARD's ring and decode
   loop, a jukebox cart.

## Reproduce

```sh
fpga/tools/mp3_bard_fetch.sh                  # third-party sources -> prototypes/mp3_bard_re/src (gitignored),
                                              # pinned: helix fb0c06b5, pvmp3 AOSP av e2f09893, lef e4f5adad
fpga/tools/mp3_bard_streams.sh                # test streams + streams.c
fpga/tools/mp3_bard_bench.sh helix all -DMP3_FRAMES=8   # host SNR + BARD image -> prototypes/mp3_bard_re/build/helix/zm_ddr.init
fpga/tools/mp3_bard_bench.sh pv all -DMP3_FRAMES=8
# run the image on a soc_hp_snd model with the board core (one sim lock), then:
ZM_SOC=$PWD/build/<model> ZM_INIT=sim_zm_ddr.init tools/cycles_sim.sh <zm_ddr.init> /dev/shm/<run>   # from fpga/
python3 fpga/tools/mp3_bard_check.py /dev/shm/<run>/uart.txt prototypes/mp3_bard_re/build/helix
```

Image md5s: pvmp3 (8 frames) b841bcf5. The sim runs' uarts are under `prototypes/mp3_bard_re/build/*/bard_uart.txt`.

## The player as built (feat/mp3-bard, 6 Nov): BARD's load with the real loop

`make snd-bench SONG=<file>.MP3 MUSIC=<dir> SND_MP3=1 ZM_FRAMES=12` (`cycles/sound/smp3bench.c`):
- the file streamed into the MP3 player as the cart streams it, the feed effects and the render
  timed together;
- pvmp3 through wasm2c inside demo-audio.wasm, the hi/lo Paula bytes;
- the combo16 core `SndNdD16Dyn8Sx`, run on the laptop.

The figures are warm 60 Hz frames 1-11, in Mc of BARD's 1.67.

| Stream | Mean a 60 Hz frame | % of BARD | Peak tick (one MP3 frame decoded) | A tick with no decode |
|---|---|---|---|---|
| TONES44.MP3 (CC0, 44.1 kHz stereo 128k) | 0.873 | **52.4 %** | 1.348 (81 %) | 0.14 (8 %) |
| Matt's track, re-encoded 44.1 kHz stereo 192k (local, a 170 KB excerpt) | 0.874 | **52.4 %** | 1.481 (89 %) | 0.15 (9 %) |

- **wasm2c costs about 1.3x the native build.** A decode is ~1.15-1.35 Mc, against the native study's
  0.89 Mc.
- **The first frame is 1.58-1.92 Mc** (95-115 %). That frame holds the stream's start and the first
  32 KiB feed, copied while BARD runs it. It happens once a track, and the 4-frame lead absorbs it.
- **Every frame decoded, nothing wrong:** status word 0x121 (playing, 44.1 kHz, stereo, 0 errors, 0
  underruns).
- **If BARD ever needs the room:** the lever is a native (non-wasm2c) build of pvmp3 bound to the player
  through a wrapped import. The native decoder is 34 %.
