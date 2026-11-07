# The MP3 PLAYER's test files

CC0: synthesised by `make.sh` here (saw-wave chords, an arpeggio and noise hits; no recording, no
sample), encoded by LAME through ffmpeg's libmp3lame, with an ID3v2.3 title and no Xing frame.
Committed as encoded, so the pins never depend on an encoder version.

| File | Stream | Frames | What it proves |
|---|---|---|---|
| `TONES44.MP3` | MPEG-1 44.1 kHz stereo 128 kbps, 8 s | 308 | the bit-exact path (`apps/mp3_check.mjs` exact), several 32 KiB reads |
| `MONO44.MP3` | 44.1 kHz mono 64 kbps, 4 s | 155 | mono: both sides the same, bit-exact |
| `TONES32.MP3` | 32 kHz stereo 96 kbps, 4 s | 113 | the linear rate conversion up to 44.1 |
| `TONES48.MP3` | 48 kHz stereo 128 kbps, 4 s | 168 | the linear rate conversion down to 44.1 |

They are on `docs/mp3-c.img` (`tools/mp3_c_image.py`) under `HD/MUSIC/`, which is `C:\MUSIC`.
Real music for listening tests stays local (never committed): `prototypes/mp3_card/HD/MUSIC/`.
