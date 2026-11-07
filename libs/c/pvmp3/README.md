# pvmp3: the MP3 decoder the MP3 player runs on

PacketVideo's fixed-point MPEG-1/2/2.5 Layer III decoder, as AOSP carries it. Integer only: 32x32->64
multiplies (MULH on BARD), no float, a handful of divides a frame. Chosen over Helix (RPSL) in the BARD
MP3 study (`fpga/review/MP3_BARD_STUDY.md`): the same cost on BARD (34 % at 44.1 kHz stereo), 1-2 LSB
from ffmpeg, and a licence that lets the decoder ship in the system image others download.

## Provenance

| | |
|---|---|
| Upstream | <https://android.googlesource.com/platform/frameworks/av/> `media/module/codecs/mp3dec/` |
| Commit | `e2f098935447ca4945946de5cb69db843fe3f003` (refs/heads/main, fetched 2026-11-06) |
| Licence | Apache-2.0: `upstream/NOTICE` (the licence text), `upstream/MODULE_LICENSE_APACHE2`, `upstream/patent_disclaimer.txt`; every source keeps its PacketVideo header |
| Local changes to `upstream/` | **none** |

`upstream/` holds `include/` and the portable C++ of `src/` (the ARM assembly in `src/asm/`, the
fuzzer and the test are not vendored). Its one build define, `OSCL_UNUSED_ARG`, comes from
`config/zm_pvmp3.h` (forced include), as AOSP's `Android.bp` gives it on the command line.

To update: fetch the new tree (`fpga/tools/mp3_bard_fetch.sh` with `PV_REV=<sha>`), copy `include/`,
`src/*.cpp`, `src/*.h` and the three licence files into `upstream/`, record the commit here, rebuild,
run `node apps/mp3_check.mjs`.
