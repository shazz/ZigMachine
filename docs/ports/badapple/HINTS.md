# Bad Apple on KESTREL: hints from the lead session

Written blind (without looking at this branch), 24 Nov 2026. Numbers marked [e] are estimates, not measurements.

## 1. What the material is

- 1-bit art: black and white silhouettes, very large flat areas, smooth contours, slow morphs between shapes,
  few hard cuts. About 6,500 frames at 30 fps (3 min 39 s).
- Raw at 320×240 1-bit: 9.6 KB a frame, ~63 MB for the whole film. At 320×200 (letterbox or crop): 8 KB a frame.
- What actually carries information: **the edges** (where a row switches from black to white) and **how they
  move from one frame to the next**. Nearly every row of a frame is a handful of transitions, and most
  transitions move by a few pixels or not at all.

So the right unit is not pixels or tiles: it is **row transitions (span boundaries) and their deltas**.

## 2. Recommended design: an LSP-style event stream of span edits

Same philosophy as LSPlayerSTE and the aurora boot: everything hard happens off line in Python; the cart only
follows a stream.

### Encoder (Python, off line)

1. Scale the source to the target (320×200, aspect handled by a letterbox or a crop; decide once), threshold
   to 1 bit with a little hysteresis so edges do not flicker between frames (a temporal hold, like the aurora's:
   keep the previous frame's edge if the new one is within 1 px, never accumulating, exact on keyframes and
   cuts).
2. Per row: the list of transition x positions.
3. Per frame, per row, compared with the previous frame:
   - unchanged row: nothing (a row-skip count);
   - same number of transitions: each transition's dx (mostly -3..+3);
   - different count: the row's full transition list (rare; at cuts and topology changes).
4. Serialise as **byte-aligned codes** first (row skip, small dx packed in nibbles, escape to a full row), then
   pack each block of 30 frames (1 s) with **ZX0**: the depacker is already in the machine
   (`romDepack` / the ZX0 tools) and costs nothing to adopt. Measure. Only if the size matters after that,
   swap the block packer for rANS / Huffman with static tables (the decoder stays tiny).
5. A **keyframe every N s** (full row lists) so a block can be decoded on its own: seeking, robustness, and
   resynchronisation after a dropped block.
6. A **Python reference decoder** that produces the exact frames the cart must produce; the harness compares
   the cart's plane with it byte for byte (the aurora boot and LSPSTE were verified this way).

Expected size [e]: a few hundred KB to ~2 MB for the whole film at 320×200, depending on how hard the hysteresis
works. Either way it fits on the card easily; RAM is the constraint, not the card.

### Player (the cart, on ZIGGY)

- **Stream from the disk**, never load the film: blocks of 1 s (ZX0) read ahead into a small ring (2-3 blocks).
  Look at how the `stream` test cart block-streams a sample off the disk and reuse that path.
- **Draw only what changed** (Matt's rule: only modify what needs to be modified). When a transition moves from
  x0 to x1, the pixels between them flip: fill exactly that run with the new colour. A frame then costs a few
  hundred short fills instead of 64,000 pixels.
- **Use the CPU for spans, not CHISEL.** A CHISEL op has ~800 cycles of fixed cost; a typical changed run is a
  few to a few dozen pixels, which ZIGGY fills with posted stores (~2.3 cycles a word, `@memset`). Keep CHISEL
  for keyframes / full-row redraws (one fill per long span) if it measures faster there.
- **One 8-bit plane, two palette entries.** Black and white are palette indices, so colour, fades, an inverted
  flash or a sepia tint are free palette writes. No second plane unless needed (each enabled plane costs
  ~0.59 Mc of compositing).
- **Tearing:** the film is 30 fps on a 60 Hz display, so apply a frame's edits during the first of its two VBLs
  and let the second show the result. If tearing shows, double-buffer with a second buffer in the same plane
  (flip the plane's base), at the cost of applying each frame's edits twice (to frame n-2's buffer), or keep
  the edits of the last two frames.

Cost [e]: decode + fills ~0.05-0.3 Mc a frame on typical frames, a few times that at hard cuts (spread a cut's
full redraw over two VBLs). The board has 1.67 Mc a 60 Hz frame; this leaves almost everything free.

## 3. A/V sync is the whole point

Bad Apple is judged on sync with the music. **Drive the frame index from the audio clock**, not from a VBL
counter: frame = audio position × 30 / sample rate (or `env.hostMicros` since the song started, if the audio
path gives no position). If the picture falls behind, skip frames' **drawing** but still apply their edits
(they are deltas: you cannot skip decoding, only presenting); if it runs ahead, hold.

## 4. The music

- **BARD plays it; ZIGGY never touches audio.** Options in the order I'd try:
  1. MP3 on BARD (~35 % at 44.1 kHz stereo 128k, measured in `docs/hardware/studies/MP3_BARD_STUDY.md`; ~26 % at
     32 kHz), the most faithful.
  2. A chiptune / FM version on our YM2612 + SN76489 VGM player (R12): tiny, period-correct for a demo port.
  3. An SNDH cover if one exists (CLAUDE.md: SNDH is the standard for ST-style screens).
- **Licence:** the song (Alstroemeria Records' arrangement of ZUN's tune) and the shadow animation are
  copyrighted fan works. Treat both like the Virtua Racing VGMs: **local-only build option**, data in a
  git-ignored place, never committed, unless Matt has a clear licence. The player code, the encoder and the
  format are ours and can be committed.

## 5. The showpiece variant: Bad Apple as a polygon stream (STNICCC style)

The repo already has STNICCC 2000 (a polygon stream). Bad Apple's silhouettes vectorise well:
- Encoder: trace each frame's contours (marching squares), simplify (Douglas-Peucker, 0.5-1 px), keep polygons
  with holes as an even-odd fill; delta the vertices between frames where the topology is the same.
- Player: fill the polygons each frame (even-odd spans, CPU or CHISEL's edge walk).
- Why: resolution-independent (the same stream at 640×400 on PEREGRINE's desk, or zoomed / rotated / mirrored
  live, which a bitmap stream cannot do), and a real demo-scene flex. Cost: more decode work and a full redraw
  each frame, so measure before committing; keep the span-delta player as the baseline.

## 6. Tests the repo will expect

- Encoder unit tests (happy + error path: empty frame, all-black frame, a cut, a row with max transitions, a
  corrupt block refused).
- Harness: the cart's plane equals the Python reference at fixed frames (first, a keyframe, mid-block, a hard
  cut, the last), sync check (frame index vs audio position), a `--break` variant that must fail; its `gate`
  line in build.sh in the same commit.
- Board: fps (OSD), the worst frame's Mc, sync by ear and eye over the whole song.

## 7. Order of work

1. Encoder + reference decoder + the size numbers (byte codes + ZX0 blocks).
2. Cart: streaming + span edits + palette, silent, frame-clocked.
3. Music on BARD (local-only), then switch the clock to the audio position.
4. Keyframes / seeking, then polish (fades, a tint, the title).
5. Optional: the polygon-stream variant for PEREGRINE.
