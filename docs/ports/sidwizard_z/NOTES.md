# NOTES.md — SWM format reference for the Zig port (Part 1)

Mirror of `asm/SWM-spec.src`, `asm/include/packdepack.inc` (packtun/depackt),
`asm/SWMconvert.c` (`ProcessSWMver1`, forward writer ~3624+) and `editor.asm`.
Zig home: `out/swm.zig`, tests `out/swm_test.zig` (`zig test out/swm_test.zig`,
needs the `out/tunes -> ../tunes` symlink for @embedFile).

## 1. File layout

    [u16 loadaddr][64-byte TUNEHEADER][packed stream]

Stream (packing order, `packtun`): sequences 0..SEQAMO-1 · patterns 1..PTAMOU ·
instruments 1..INSTAM · chords[1..CHRDLE] · tempo RESTEMP+1..+TMPLEN ·
funktempo pairs (ceil(SEQAMO/3)×2, min 1). Parsed backwards from the end like
`ProcessSWMver1`; the reader must land exactly on the TUNEHEADER's last byte.

## 2. TUNEHEADER map (byte position, what the port does with it)

| pos | label      | meaning / save behaviour                                      |
|-----|------------|---------------------------------------------------------------|
| 0-3 | SWM_ID     | "SWM1" magic, checked (`BadId`)                               |
| 4   | fspeed     | fullscreen speed, verbatim                                     |
| 5   | hili       | highlight (editor RASTER colour, verbatim)                     |
| 6   | auto       | auto-department / auto-apply, verbatim                         |
| 7   | confbits   | config bits — see quirk Q6                                     |
| 8-10| mute       | 3 mute flags, verbatim                                         |
| 11  | deflen     | DEFAULTPTNLEN (blank patterns put $FF at this row)             |
| 12  | SEQAMO     | *recomputed at save* (`packtun`) — see §4                       |
| 13  | PTAMOU     | *recomputed*                                                    |
| 14  | INSTAM     | *recomputed*                                                    |
| 15  | CHRDLE     | *recomputed*                                                    |
| 16  | TMPLEN     | *recomputed*                                                    |
| 21  | hili2      | 2SID highlight (1SID: observed 00)                              |
| 24-63| AUTHORINFO| 40-byte author/title text, verbatim                             |

## 3. Stream block formats (all validated byte-exact against 11 tunes)

* **Sequence** `[L bytes incl. trailing $FE | L]` (or `$FF + addr` counts as
  L = y+2; at cap seqlength=126 the packer forces a bare $FE, L = 127).
* **Pattern** `[raws.. | Size | Length]`: expanded slot = Size bytes with $FF
  at Size-1, Length = effective row count. Raws: run packing by `ptpcklp` —
  non-zeros and isolated zeros literal; a zero run > 2 becomes one marker
  $70..$77 = (v−$6E) zeros, legal only while the previous RAW byte is $00 or
  another marker (the depacker judges it, original quirk kept, Q-quirk (e)).
* **Instrument** `[Size raws | Size | 8 name bytes]` (size byte overwrote the
  $FF endmark; slot holds raws + $FF at Size + zeros to 119 + name at 120).
* **Chords/tempo/funk**: byte ranges cut at CHRDLE / TMPLEN / 2·subtunes
  (`packtun` copies 255/119 bytes but only advances compzptr by the counts,
  so the file holds exactly CHRDLE / TMPLEN bytes — proven by menu.inc's
  KERNAL.SAVE-end-at-compzptr + the 11-file round trips).

## 4. Count recomputation (save) rules — all proven on 11 tunes

* **SEQAMO** = last slot whose scan (`scanSeq`) length ≠ 1 (bare $FE = empty);
  a slot holding only `$FF+addr` still counts.
* **PTAMOU** = max over every scanned orderlist byte v with 1 ≤ v ≤ 100
  (delimiters and the $FF jump byte never scanned; SEQ-FX ≥ $65 skipped).
* **INSTAM** = last instrument 1..36 whose `instSize` ($FF search from y=119
  down, bail-out Size=15 at y==15) ≠ 18 (the dummyihdr endmark position).
* **CHRDLE** = position of the last chord-end delimiter: v ∈ {$7E,$7F} whose
  predecessor is bit7-set or < $7E (i.e. not another $7E/$7F). A delimiter
  counter X counts EVERY $7E/$7F; the scan stops once the last allowed chord
  end is recorded (empirically: record while X ≤ 31 — FUTUCO records its
  31st; the literal asm `cpx #MAXCHORDAMOUNT-1'd abort mis-trims, see Q7).
* **TMPLEN** = last tempo delimiter (any bit7-set byte) excluding plain $80
  that follows another bit7-set byte (empty program) or sits at y=0;
  record-while-X ≤ 63, same shape as CHRDLE.

## 5. C64 workfile image (`toC64`/`fromC64`)

Fixed MUSICDATA = $1D00, whole image = $8680 = 34432 bytes (settings.cfg,
COMPILEDAPP==1, SID_AMOUNT==1). Offsets: SUBTUNES 0 (8 rows×8: 3× lo/hi
orderlist pointers + funk1/2), PPTRLO 64, PPTRHI 165 (101 each: 0→PTN0,
i→RESTPTN+(i−1)*256), INSPTLO 266, INSPTH 304 (38: dummy 0 rides instr 1's
base — Ian Coog advice, open question Q2; 1..36 → INSTRUMENTS+(i−1)*128; 37 =
one-past-last), CHDPTLO 342 (33 LO only), TEMPTRLO 375 (65 LO only),
ptnlength 440, ptnsize 541 (101 caches), TUNEHEADER 642, SEQUENCES 706,
PTN0 3778 ($00,$FF), RESTPTN 3840, INSTRUMENTS 29440, CHORDS=endinstrum
34048, TEMPOTBL 34304, RESTEMP 34312 (+8), endoftune 34432.
fromC64: re-derives seq_len by scan; trusts ptn_size cache (validates $FF at
size−1); copies instrument slots wholesale (sizes re-searched at pack time).

## 6. Known quirks kept on purpose (Q-numbers used in code comments)

Q2 INSPT[0] wiring (dummy instrument) is an unverified open question.
Q3 CHDPTR[0]=0, CHDPTR[1]=1 are editor-side init, not from the depacker.
Q4 TEMPTR[0]=TEMPTR[1]=9 ("pointer 0 and 1 always the same", depktempo) —
   RESTEMP+1 relative to TEMPOTBL.
Q5 TEMPOTBL bytes 0..8 (rest-tempo words + RESTEMP+0) are player runtime;
   toC64 zeroes them deterministically; fromC64 never reads them.
Q6 confbits bit7 (OPTIMIZEPTN) is NOT re-applied by load — the packed-NOP
   legality (previous-raw-byte rule) is decided purely by stream context.
Q7 Chord/tempo "record-while-X ≤ max" vs the asm's literal `cpx #max-1`
   (see §4; FUTUCO proves recording the 31st chord end).
Q8 chords[256] (past the table) is read by the asm's wrapping scan loop;
   the port treats it as a non-delimiter.
Q9 SEQAMO=0 tunes: subtune count clamps to 1 so a funktempo pair still saves
   ("still possible for the 1st empty subtune"); chord0 stays $7F so an
   empty chord table recomputes CHRDLE=0 (NEPZENEK, VN-WAITING prove it).
Q10 A pattern's Size byte landing in $70..$77 is judged as a raw marker
   context ("first raw byte sees the size byte") — latent original quirk.

## 7. What we do NOT yet replicate (deliberate)

* Values ≥ $7F inside loaded chords are handed to the player verbatim; a
  real editor can only reach $7F there via corrupt input.
* `save` never re-packs instruments above INSTAM (packtun writes and then
  overwrites them; the file never contains those bytes).
* >32 chords / >63 delimiters can't exist in a well-tuned save; the X-abort
  is a safety belt for corrupt memories, approximated as in §4.

# NOTES.md — Part 2: display.zig (Screen + View + render/overlayRender)

Zig home: `out/display.zig`, tests `out/display_test.zig` (16 tests, all
green; fixture = tunes/FLASHITBACK.SWM via `out/tunes` symlink).

## 8. API contract

* `Screen = { chars: [25][40]u8, colours: [25][40]u4 }` — screen codes and
  colour RAM exactly as the C64 shows them (25 rows; the asm's "26th row"
  lives at videoram page 2 and is exposed via the Overlay instead).
* `render(song, view, screen)` — pure; repaints the full static screen:
  template copy (iniscrn) → ptndisp → stpdisp → mutesolodisp → insdis
  (instrument panel) → miscdis → row25back.
* `overlayRender(song, view, over)` — everything the editor draws with
  sprites + the hidden 26th row: seqdisp/dispaut, ordldis, upbordisp,
  cursord, and ptncurs (the byte index of the cursor row in pattern
  memory — Part 3's datawriter input).
* `View` fields mirror asm variables one-to-one (see the struct comments).
  Host-runtime Overlay fields (songtime, PW/CTF meters) are presetted by the
  caller and left untouched, mirroring playadapter.

## 9. Display findings (asm ground truth, mostly probed on FLASHITBACK)

* **Charset/vidram semantics**: SW's charset is custom. Screen codes $41-$5a
  render as mirrored/inverse letters, $30-$39 as inverse digits, $2e as an
  inverse period. The template's `.enc "screen"` strings store A-Z as
  $01-$1a and digits as ASCII ($30+). Instrument names / author text are
  copied **verbatim** from song memory (packinst/depkins copy, insdis copies
  name bytes raw) — the real C64 shows ASCII bytes as the inverse glyphs.
  Verified against the real screenshot
  (prototypes/sidwizard_re/shots/02_editor_flashitback.png): the panel shows
  the mirrored "ARP....." and the author line reads correctly. **Tests must
  compare raw bytes, not rendered text.**
* notechar/octachar tables are byte-exact vs asm/graphics/graphics.inc
  (mechanical diff; octachar[$3b]=$b4, notechar[$3b]=$89,
  notechar[$7e]/octachar[$7e]=$5f/$60 gateoff).
* **mutesolo polarity**: bit0 SET = **unmuted** (editor.asm inits $FF,$FF,$FF;
  msolocol: mutecol,15 / mutecol,3 — index 1 = normal). Muted → mutecol (11).
* **condisa colours**: control byte bit7/bit6 SET → gateoff (11), CLEAR →
  ina (15) (conboff=15 / conbons=11, conad[0]=COLRPOS+$316 row 19 c30-33,
  conad[1]=$24e row 14 c30-33).
* **wf1 pair (row 1 c38/39)**: control bit3 SET → the waform1 hex pair
  (ins[15]: hi raw digit char, lo $90|lo nyb); bit3 CLEAR → the $69,$69
  chars. Asm trick: `conbons` has only 3 bytes, so conbons[3]/[4] ARE
  waform1, patched live by wf1disp.
* **miscdis uses RAW selsubt** for the subtune digit (`lda #selfmod; ora
  #$c0`); the port clamps only the funk-table read (memory safety). Same for
  funk chars: `TEMPOTBL+0/+1 | $c0`, bit7 set → $20 space at $3e6.
* **Pattern display**: window top = walkPtn(base, prowpos[t]) — the display
  scrolls with the played position. Endmark row → the 8-glyph ptendch string,
  rows below blanked to $bd (afterptn). Corrupt pattern without endmark:
  blanked once past ptn_bound-4 (the asm would wrap into the next pattern;
  deviation, see D1). Dummy pattern = PTN0 = $00,$ff.
* **Cursor (cursord)**: x = col*8+24, y = row*8+34, $d01d = double-wide in
  note column. Pattern window: y = subwpos3[0] clamped 0..24, x from
  stplptr track + subwpos2. Orderlist: raw Y (0..2 PAL rows). Instrument
  window: inswXbuf+iswposx (+2 quirk when ≥36 in subwindow 0),
  inswYbuf+iswposy. Chord: row+6, x=38+. Tempo: row+20, x=38+.
* **upbordisp**: ptnsize readout = ptn_size[curptn1]-1 with lo nybble char
  LEFT, hi RIGHT; octave = jamoctave+1; patnum = curptn1.

## 10. Port deviations (D-numbers)

D1 walkPtn stops at the $ff endmark / ptn_bound-4 instead of wrapping into
   the next pattern's memory (the asm walks blindly; that's corrupt-memory
   behaviour only).
D2 Cursor row/col inputs are clamped to the visible screen (the 6502 writes
   raw bytes into sprite registers, wrapping at 256). Startup behaviour is
   identical; only garbage Views differ.
D3 stptick=0: the 6502's division produces garbage; the port guards with
   @max(stptick,1).
D4 The subtune digit keeps RAW selsubt (faithful), but the funk pair is
   read from the clamped subtune (can't read past song.funk).
D5 A full render() includes the instrument panel (insdis): on the C64 it is
   redrawn on instrument change / edits, not every frame; the port's render
   is a "draw everything" pass.

## 11. Zig 0.16 gotchas hit

* **Operator precedence is NOT C**: `>>` binds tighter than `&`, and `|`
  binds tighter than `&`. `x & 0x7f >> 4` is `x & (0x7f >> 4)`. Every
  compound bitwise expression needs explicit parens. (Cost an afternoon.)
* `@splat` doesn't work for nested arrays; write
  `[_][N]u8{[_]u8{0} ** N} ** M`.
* Slices need `.*` to compare as arrays (`scr.chars[0][32..40].*`).
* `song.load(...)` — no; Part 1 API is free functions: `swm.load(&song, x)`.


# NOTES.md — Part 3: keys.zig (keyhandler port, complete)

Zig home: `out/keys.zig`, tests `out/keys_test.zig` (11 tests, all green;
fixture = tunes/FLASHITBACK.SWM). Scope: default SW keyb layout (KeybTyp=0),
COMPILEDAPP=1, SID_AMOUNT=1, no MIDI, `repeatex` → no-op (Part 4 host does
key repeats). API: `kh.Key{code: u6 (C64 matrix col*8+row), shift, cbm}` +
`kh.handle(song, view, key) Effect`.

## 12. Key map (keyjmp order, col*8+row)

| col | codes 0..7 | codes 8..15 | asm handler chain |
|-----|------------|-------------|-------------------|
| 0   | 0 DEL → deleter (cbm→delerow, shift→inskeye, else delRow/delLast/delordl) | 8 '3' → digitKey | every code has its keysub; codes 15/52/61 = lshift/rshift/C= themselves (morekey, no-op) |
| 0   | 1 RETURN → reter (orderlist write/norcrdn) | 9 W → wKey (note 15) | |
| 0   | 2 CRSR→ → cursori (shift = left) | 10 A → aKey (writevalue fixup → note 1) | |
| 0   | 3 F7 → f7er (shift = .menu) | 11 '4' → digitKey | |
| 0   | 4 F1 → f1er (play song / shift = markers) | 12 Z → zKey (note 1; cbm = undo; shift = autoadv−) | |
| 0   | 5 F3 → f3er (play pattern / shift = stop-or-cont) | 13 S → sKey (note 2; shift = smallfx delete) | |
| 0   | 6 F5 → f5er (instrument window) | 14 E → eKey (fixup → note 4) | |
| 0   | 7 CRSR↓ → cursrdn (shift = cursor up) | 15 lshift → morekey (.none) | |
| 1   | 16 '5', 17 R (18), 18 D (fixup→5), 19 '6', 20 C, 21 F (fixup→6), 22 T (20), 23 X (3; cbm = cut) | 24 '7', 25 Y (22), 26 G (7), 27 '8', 28 B (8), 29 H (9), 30 U (24), 31 V (6) | digitKey: shift+1..3 = mute, shift+0 = solo, cbm+1..8 = octave (d−1; cbm+9 → 8 verbatim), plain = writevalue |
| 2   | 32 '9', 33 I (25), 34 J (11), 35 '0', 36 M (12), 37 K (ring FX; plain no-op), 38 O (27), 39 N (10; cbm = chord-note mode, shift = nametype) | 40 '+' → pluser, 41 P (29), 42 L (14), 43 '-' → minuser, 44 '.' (15; cbm = subtune−1), 45 ':' (17; funktempo2+1), 46 '@' (30), 47 ',' (13; cbm = subtune+1) | funktempo pair only when tempo1 bit7 CLEAR |
| 3   | 48 '£' → inskeye (INSERT), 49 '*' (32), 50 ';' (sync FX; funktempo2−1), 51 HOME → homer, 52 rshift → .none, 53 '=' → equaler (negate table cell), 54 '↑' → page-down, 55 '/' → slasher (shift = page-up) | 56 '1', 57 '←' → fastfwd, 58 CTRL → ctrler (TAB), 59 '2', 60 SPACE → spacer (play pattern / jam), 61 C= → .none, 62 Q (13), 63 RUN/STOP → stopper | |

Note values in brackets = default-keyboard note column entry (via
writevalue/notecol). R/S/K plain = FX-column specials (ring mod / sync /
no-op). Full per-key behaviour lives in the keysub port functions; every one
cites its asm routine.

## 13. Part 3 semantics worth recording (byte-verified vs asm)

* **writevalue fixups**: after the NoteOfY lookup the asm edits X for keys
  A (cpy #$A; inx → note 1), D (cpy #$D; inx → 5), E (ldx #$04 → 4) and
  F (ldx #$06 → 6). The `.proc` header comments ("note-entry D#") are
  STALE; the code is ground truth. Affects note entry, isincol jam byte
  and NOT hex-column writes.
* **SaveUndo**: the asm repecnt gate (cmp #repspd1−1) means EVERY fresh
  keypress re-saves the undo buffer; repeats don't. The port always saves
  (deviation noted in code, identical for distinct presses). Consequence
  (proven by test): undo restores the state BEFORE THE LAST mutating
  keypress only — '1','2',undo → the post-'1' state.
* **delinpt (plain DEL main path)**: delete the row, then `inc ptnsize` and
  append NOP + $ff at the end — ptnlength (row count) is NEVER touched and
  the cursor does NOT move (path ends at jmp instpt2). The asm's in-memory
  ptnsize is exclusive ($ff sits AT [ptnsize]) while the port's ptn_size is
  inclusive (endmark at [ptn_size−1]); both produce the same bytes:
  NOP at [size−1], $ff at [size], size+1.
* **delinpt endsignal branch (dellast)**: compcur Z (cursor row == ptnlength)
  does NOT abort — it deletes the LAST row (getlast walk + getdelamount +
  delbackpt), `dec ptnlength`, guards ptnlength==1 / subwpos3==0. Cursor
  follows the endsignal: prowpos≠0 and subwpos3<13 → nodecpu (scroll up),
  else upinptn (cursor up). Note `cmp #13 / bpl` is a SIGNED compare: < 13
  scrolls, ≥ 13 moves the cursor.
* **nodecpu/noincpu track-binding**: NOT the "tracks 2,1 only" bug it was
  first read as — the asm loop exits with X=0 and FALLS THROUGH into
  ptscrup/ptscrdn ("X is 0 here, to do 1st track too"), so all three tracks
  scroll. Port fixed and covered by the dellast test (needs prowpos=40).
* **Funktempo polarity**: tempo1 bit7 SET = single-tempo mode (tempo2
  hidden/unused); CLEAR = funktempo pair active, alternating row-by-row.
  colon/semicolon (tempo2 ±1) refuse $80 / cap < $c0; dot/comma edit tempo1
  low6 (cap $3f; full-byte refusals: v==0 bcc, v==$80 bvs); cbm+T toggles
  bit7. TEMPOTBL+0/+1 stores are outside the port's tempo[] area (skipped).
* **nametyper (menu.inc)**: shift+N (or F5 at the top of the instrument
  window) stages insts[selinst][120..128] into View.namebuf; keychar[code]
  gives screen-code chars; RETURN ($ff) stores, $fe (stop/F7/backarrow)
  escapes unsaved, $f5 home, $f7/shift+backspace insert, $fd backspace,
  $fc cursor sideways. The asm's CRSR↓-no-shift branch references a missing
  `++` label in this asm copy — treated as no-op.
* **cbm+9** sets octave 8 verbatim (`sty jamoctave+1` with Y=9, d−1 skipped
  only for d=0); the port clamps downstream reads.
* **Zig gotchas added**: `+%` binds tighter than `^` — `v ^ 0xff +% 1` is
  `v ^ (0xff +% 1)` → 256 overflow; write `(v ^ 0xff) +% 1` (hit twice:
  equaler/NegItbl, NegChrd). `11 + w` with w:u8 inferred u2 from a `@min`
  result — coerce with `@as(usize, w)`. `@memcpy` src/dest must be slices,
  not `&arr[i][0..N]`. Zig lazily analyses: `_ = module` compiles clean
  while called paths still hide type errors — the real test target surfaced
  8 latent ones (ptnMpos/ptnCur usize→u8, seq_len usize→u8, memcpy
  addresses, olinser's missing cbm arg, ctrler switch arm types, getitbi
  const-view).

## 14. Part 4 needs (was the forward-ref list; now all done — see §15)

* menuInc/menuDec — implemented in menu.zig, delegated from keys.zig.
* Effect payloads the host must implement: play_song/play_markers/
  play_pattern/stop_or_cont/fastfwd (playadapter), menu/load_dialog/
  save_dialog/quit (Part 4 menu + dialogs), nametype (host feeds keys back
  into handle() while view.namemode).
* menukeys allowlist stays in handle(); the menu's own key handlers are in
  menu.zig (cursor) + keys.zig (wiring).

## 15. Part 4 — the main menu (menu.zig)

Source: asm/include/menu.inc (menutxt/dispmenu/menujmp/runmenup, the item
routines, RyouSur/YesOrNo, CINITUN/CININST, helptxt) plus the menuinc/menudec
half that lives in keyhandler.inc. Split of duties: menu.zig owns menu state
transitions and pure rendering; the host owns file I/O. Menu state lives in
`display.View` so keys.zig can drive it without display.zig importing
menu.zig (that would be an import cycle).

**Geometry** (settings.cfg menuxpos/menuypos; menu.inc derived):
`menuxpos=9, menuypos=2, menuxsize=19, menuysize=22, helpYsize=20,
firstcpos=3 (SAVE TUNE), lastcrpos=20 (INSTANT HELP!), drivemenupt=7,
ptlenmenupt=10`. The block is 22 rows × 19 columns at (row 2, col 9), i.e.
screen rows 2..23, columns 9..27. `draw()` paints it row by row; the row
under `menucurpos` uses the theme cursor colour, everything else the theme
background colour. Rows outside firstcpos..lastcrpos never highlight (guards
a hand-made View).

**Item map** (menujmp order; menupoint = menucurpos − firstcpos + 1):

| # | row | item | effect |
|---|-----|------|--------|
| 0 | — | dummymp | nothing (RETURN on a non-option row) |
| 1 | 3 | savetun | `.save_dialog = .tune`, menu closes |
| 2 | 4 | loadtun | `.load_dialog = .tune`, menu closes |
| 3 | 5 | saveins | `.save_dialog = .instrument`, menu closes |
| 4 | 6 | loadins | `.load_dialog = .instrument`, menu closes |
| 5 | 7 | seldriv | IncDriv (RETURN also steps the drive) |
| 6 | 8 | AutoDir | confbits2 ^= 1 |
| 7 | 9 | SetFspd | IncFspd (framesp 1..8) |
| 8 | 10 | SetDefPtLen | IncPtln (defptlen) |
| 9 | 11 | initunt | menuprompt = 1 (ask first) |
| 10 | 12 | iniinsc | menuprompt = 2 (ask first) |
| 11 | 13 | SwitchTheme | themeno = (themeno+1) % 9 |
| 12 | 14 | KeyLayout | 0→$2c→$44→$88→0 |
| 13 | 15 | AutoIns | confbits ^= $80 |
| 14 | 16 | AutoFollow | confbits ^= $04 |
| 15 | 17 | RasterBar | confbits ^= $02 |
| 16 | 18 | ChordNoteMode | confbits ^= $40 |
| 17 | 19 | SaveConfig | `.save_dialog = .config`, menu stays open |
| 18 | 20 | Helper | helpmode ^= 1 |

`menu.run()` returns a `menu.Action`; keys.zig `menuAction()` maps it to
`kh.Effect` (`.redraw` for state-only rows, `save_dialog`/`load_dialog` with a
`FileKind` payload for the four file rows and SaveConfig). Rows that only
change editor state keep the menu open, exactly like the asm's `jmp mainloop`.

**`+`/`-` and cursor left/right in the menu** (keyhandler menuinc/menudec,
non-2SID build): only the SELECT DRIVE and DEF.PATT.LEN rows have their own
editor (IncDriv/DecDriv, IncPtln/DecPtln); every other row falls through to
`pluser.incinst`/`minuser.decinst`, i.e. it changes the selected instrument.
Drive: 8..30 inclusive, 30→8 and 8→30. Defptlen: `IncPtln` computes
`defptlen+1` and rolls to 1 when the increment reaches maxptnlen (249, so
248→1); `DecPtln` rolls 1→249 then decrements (1→248). The pattern-length
editor's own cap is `maxptnlen` in the asm, but the effective window is
1..248 for +/-.

**confbits relocation (important)**: `Config.confbits` is *editor* config,
not a tune-header byte. It now lives in `View.confbits` (default
`display.default_confbits = %00001001`); all 14 keys.zig uses were migrated
(untouched-header sites are the ones that really are `TUNEHEADER+6/+7`
`leavemp`, saved verbatim). The menu and the keyhandler XOR the same View
word, so AutoIns/AutoFollow/RasterBar/ChordNoteMode, follow-play default
(`$04`), track-binding (`$01`), auto-instrument-after-note (`$80`) and the
chord note/number display (`$40`) all read one place.

**Kill-tune quirk (CINITUN)**: zero `SEQAMO`/`PTAMOU`/`TMPLEN`, then rebuild
the blank state the way a load's depackers would: every pattern wiped to the
*editable* defptlen (`TUNEHEADER+11`, not the compile-time 32), every
orderlist `$FE`, tempo table `$80`, then a default subtune of patterns 1..3.
`depktempo` re-reads subtune 0's funk pair from the packed stream — after
zeroing the counts that is the tune's own `funk[0]` pair — so **funk[0]
survives** while `funk[1..7]` are reset to `default_funk` ($86/$83). CININST
zeroes the instrument and chord counts and rebuilds instruments 1..36 plus
chord end signals (chord 0 keeps its `$7f` delimiter). Both are `swm.killTune`
/ `swm.killInsts`.

**"Are you sure" prompt**: `view.menuprompt` is 0 (none), 1 (kill tune) or
2 (kill instruments). `handle()` gates on it *before* the menukeys allowlist:
only Y (25) / I (33) accept, N (39) / V (31) reject, every other key is
ignored (YesOrNo blocks). Either answer closes the menu and returns
`.redraw` (both asm paths go back to the editor). `menu.drawPrompt()` paints
the 17×4 box: top = ypos + rows/2 − 2 = 11, left = xpos + 1 = 10, colour 1,
borders of `*` with `* ARE YOU SURE? *` / `*  (Y/N) (I/N)  *` inside.

**Theme table**: `ThemeNames` is exactly 72 chars (9 names × 8), split
`"DEFAULT BRIGHTERGREENISHTURKISH  BLUISH  PURPLE BROWNISHRED&GREYAMISH :)"`
— note there is no space between GREENISH and TURKISH in the asm's table
(the name strings are fixed 8-byte cells). menu.zig keeps only the menu
colours per theme (`ColorThemes` columns 14/15 = menubg/menucur) plus `fxcol`
(column 3) because those are what the menu block itself needs.

**Deliberate omissions / deviations**:
* `clearmenu`/`$bd` erase path: the host repaints the whole screen, so
  closing the menu just clears `menumode`/`helpmode` and asks for `.redraw`.
* Full editor-palette switching per theme (coloriz/iniscrn/insdisp/stpdisp):
  Part 2's `display.Palette` stays theme 0; the menu uses its own per-theme
  bg/cur/fx table. Changing theme repaints the menu, not the editor.
* SaveConfig's real file write: host's job. `menu.setCfgStat(view, ok)` sets
  the `!` cell the asm writes on a failed save.
* `helpmode` is a bool in View; the asm stores it as a self-modified flag.
* The help row for SID_AMOUNT=1 is `"SH+1..3 MUTE/UNMUTE"` — the asm's
  `SID_AMOUNT*3+"0"` evaluates to the single character `'3'`, not `"30"`.
* `swm.killTune`/`killInsts` do not clear the undo snapshot; the port keeps
  Part 3's single-level undo semantics (undo after a kill restores the
  pre-kill state, which is what the asm's buffer would hold too).

## 16. Part 4 (continued) — the file dialog and the start-up menu

### filer.zig — menu.inc filedialog/filenamer
`filer.State` lives in `View.filer`; `keys.handle()` routes every key to it
while `view.filer.open`. It is a pure state machine: the host supplies the
directory (`filerListing` → `filer.setListing`) and performs the load/save
(`filerResult`). No KERNAL calls, no file I/O.

* `Kind` = tune/instrument/config (extension `.SWM`/`.SWI`/`.CFG`).
* `Mode` = load/save. A **load** always asks for a listing; a **save** only
  when `confbits2` bit0 (`Save_AutoDiskDir`) is set, otherwise the name typer
  opens immediately (F1 asks for a listing later). `defawin` is modelled by
  `setListing`: a load with a non-empty list switches to the selector, a save
  stays in the name typer.
* Windows: `name_typer` → (`author_typer` only when `editauth`, i.e. saving a
  tune) → `selector` → back. `setsele` refuses an empty list, so TAB never
  reaches an empty selector.
* Selector stepping is the asm's `fiselLR`: CRSR↓ moves 3 entries, CRSR→ one;
  Shift reverses. Selecting writes the entry name into `filenamp`, which is
  what `regname` later registers.
* `regname`: trim trailing spaces, append the 4-byte extension. An empty name
  is refused (RETURN does nothing). `regauth` copies `authorip` into
  `TUNEHEADER+24..63` only when `editauth` is on (tune save), including on
  STOP/abort, exactly as the asm's `regauth` does.
* Effects from `keys.zig`: `.need_listing`, `.load_file{kind,name}`,
  `.save_file{kind,name}`, `.close_filer`. `filerResult(view, ok)` records
  `not_found`/`save_error` for the host's error line. The old
  `.load_dialog`/`.save_dialog` variants remain for hosts that drive the
  dialog themselves.
* Key mapping uses `keychar`: TAB ($fa), CRSR↓ ($fb), CRSR→ ($fc),
  DEL/backspace ($fd), HOME ($f5), INSERT ($f7), F1 ($f8), F3 ($f9),
  STOP ($fe), RETURN ($ff); printable chars are typed as-is.
* The dialog's screen (`display.filerRender`) is a compact text layout (name,
  author, three 19-row columns, status line). The original's disk header,
  free-space display and file-size columns are host data and not reproduced.

### startup.zig — startupmenu.inc
State: player selection (0..5, `Config.PlayerType`), tuning (0..3,
`Config.TuningType`), config-found flag, PAL/NTSC/Drean, and the description
scroller. CRSR↓/Shift+CRSR↓ cycles players (wrapping), CRSR→ cycles the
tuning, RETURN/SPACE starts the editor. `render` paints the title, config
result, the six player names with raster time/size, the two-line scrolled
description, the machine line and the tuning line. `tick` advances the
scroll one column per frame (0..40).

Not ported: the raster fader, the `$d016` skew effect, the graphical
`menugraph` feature-tick grid, and `altplayers.inc`'s player-code copying.
In the native port the 6502 player is fixed, so the selection is
informational (the host can use it to choose a tuning/frequency table).

## 17. Part 5 — Editor glue, review and known gaps

### editor.zig
`Editor` owns `Song` + `View` (+ an optional `startup.State`). API:
`init()`, `load(bytes)`, `save(buf)`, `key(Key)`, `render(*Screen)`,
`overlay(*Overlay)`, `songForPlayer(*[65536]u8)`, `playerState(mem)`,
`syncPlayback(mem, playing)`, `filerListing`, `filerResult`.

Player variables (editor build: `PLAYER_VARS_BASEADDRESS=$10`,
`PLAYER_FOR_ROM=0`, 7-byte channel bunches in player.asm):

| variable | address per channel | offset from $10 |
|---|---|---|
| SPDCNT | $26 + 7·c | 22 |
| SEQPOS | $27 + 7·c | 23 |
| PTNPOS | $28 + 7·c | 24 |
| CURPTN | $3A + 7·c | 42 |
| TMPPOS | $65 + 7·c | 85 |

`syncPlayback` mirrors playadapter.padapter: `olstart` ← SEQPOS,
`played_curptn` ← CURPTN, `ptrowpos` +1 when `playing` and SPDCNT equals the
tempo byte at `TEMPOTBL+TMPPOS` (masked $7f), and `ptrowpos` = 0 whenever
PTNPOS is 0. `songForPlayer` writes the tune at `music_data` ($1D00); the
host still loads the player code at $1000 and calls its initer.

### Self-review fixes made in Part 5
* The Part-4 menu rows returned dialog *requests*; they now open the filer
  directly and the host only sees listing/load/save/close effects.
* STOP in the filer now clears `filer.open` (the close effect used to leave
  the dialog latched).
* `filer.setListing`/`stepSelection`/`cycleWindow` keep `filenamp` in sync
  with the selected entry, so RETURN in the selector registers the right name.
* `solosta` was already corrected to 0/1 in Part 3; `confbits` already lives
  in `View`, not the tune header.

### Known gaps (ranked)
1. **Start-up player selection is informational.** `altplayers.inc`'s player
   code copy, per-player feature instances and the feature-tick grid are not
   ported; the native editor always runs the default 6502 player. Tuning
   choice is carried in `startup.State` for the host to apply to its
   frequency table.
2. **File dialog rendering is simplified.** The KERNAL directory reader,
   disk-name/free-block header, per-file block counts, overwrite
   confirmation, SW-emulator folder entries and exact cursor painting are
   host-side. The logic (windows, typing, selection, extension append,
   author registration, error statuses) is ported.
3. **Play display needs a per-frame host call.** `syncPlayback` implements
   the row counter and markers, but the host must call it once per frame with
   the real `playmod` state; scope/volume meters, sprite cursor and the
   hidden-row/upper-border sprites still come from the host's video layer.
4. **Instrument and config file contents are host-side.** The filer returns
   names/kinds and effects; `packinst`/`depkins` and `.CFG` serialisation
   were outside Parts 1–5 (the `.SWI`/`.CFG` formats are not in `swm.zig`).
5. **Theme switching only repaints the menu.** Full editor-palette switching
   (`coloriz`/`iniscrn`/`insdisp`/`stpdisp`) remains deferred; the editor
   stays on theme 0's palette.
6. **MIDI, multi-SID, emulator-only paths and the SID-Maker/exporter build**
   are not ported (the port targets the 1-SID, COMPILEDAPP=1 editor).
7. **Start-up menu graphics.** The raster fader, `$d016` skew, splash/logo
   and the 19×12 feature grid are not represented in `Screen`; only the text
   state machine and its information are.
8. **File-name encoding.** `filer.Name` stores PETSCII/ASCII uppercase; the
   host must map it to its filesystem's case/encoding and enforce its own
   path rules.

## 18. Part 6 — pixel-true screens (VICE ground truth)

### 18.1 Font: taken, not rebuilt (`editor_charset.bin`, 2048 bytes)
Official `SID-Wizard-1.9.prg` run in VICE 3.9 (`x64sc -warp +sound`, remote
monitor on 127.0.0.1:6510). The start-up menu waits on a CIA keyboard scan the
VICE key-feed cannot reach, so the menu's `cmp #$fd` (RETURN) at $2DDE was
patched to `cmp #$ff` in the running machine, which starts the editor. In the
editor the IRQ switches VIC state per raster zone; the main zone is
`$dd00 & 3 = 0` (bank 3, $C000) and `$d018 = $85`: screen $E000, charset
$D000 (RAM under I/O). `bank ram` + `bsave "cs.bin" 0 d000 d7ff` = the file.
Cross-check only: it equals the first 2048 bytes of `asm/graphics/sw-charset.prg`
(no inversion needed; code 0x41.. are the inverse letters the build draws).
Also dumped (tests use them): `vice_empty_vram.bin` ($E000..), 
`vice_empty_cram.bin` ($D800..), `vice_empty_ordlspr.bin` (bank 0 $0400..$05BF),
`vice_empty_updispr.bin` ($D900..$DAFF): the blank tune in the editor.
`sw_header.bin` = `asm/graphics/sw-header.prg` minus its load address (the logo
sprites). All SID-Wizard bytes (WTFPL, Hermit). The C64 character ROM (start-up
menu + file dialog, `$d018=$17`) is Commodore's: `shot_png.py` reads it from the
local VICE data dir and nothing of it is copied into this tree.

### 18.2 The A-Z -> 1..26 conversion is gone
64tass `.enc "screen"` keeps capitals at $41..$5A and maps only a-z to 1..26;
the editor's vram is ASCII for every capital (VICE `vice_empty_vram.bin` row 5
reads 57 46 41 52 50 44 54 "WFARPDT"). Removed: `screenCode` (menu.zig),
`scrCode` (display.zig, startup.zig); template runs "INSTRUM.", "WFARPDT",
"PULSEKT", "FILT.KT" and `drvsig` N M L E B D are ASCII now. startup.zig keeps
`screenCode` for a-z only (the start-up menu text is mixed case). Tests changed:
menu_test.zig (`expectRowAt`: dispmenu copies menutxt verbatim), startup_test.zig
(`startup.screenCode`, plus a new test), display_test.zig ("row26 author/title":
drvsig[1] is 'M', menu.inc drvsig).

### 18.3 Why the top and bottom rows were missing
Not a crop bug in shot.zig: those rows are not in the 25x40 text screen at all.
Upper border (y 14..34 of the 400x280 frame): the SID-WIZARD logo and the
`P01 Size:..` / drive / time / PW + cutoff meters / oscilloscope are **7
X-expanded sprites** ($D940.., sprite Y 25) filled by `upbordisp`
(displayer2.inc). The three orderlist rows under the 26th row are 7 more
sprites (bank 0 $0400.., Y=1 which wraps to raster 257) filled by `ordldis`.
shot.zig only drew the text rows. `border.zig` now ports `upbordisp`/`ordldis`
(byte-checked against the VICE dumps: ordlspr 100 %, updispr all but the 8 live
oscilloscope bytes) and `frame.zig` composes text + 26th row + sprites into the
400x280 picture (the 26th row = glyph lines 1..7 at y 237..243 between two
colour-15 raster bars; the low-border sprites sit behind the VIC idle byte
$3FFF = %10000001, so columns 0 and 7 of every 8-pixel cell are blank).

### 18.4 Bugs the reference exposed (fixed)
* `chTmDisp` (chord + tempo tables) was never called by `render()`: now it is.
* Instrument-panel colour RAM: cols 38..39 of rows 1..4 are colour 12 (fx)
  except HRTY's value; PULSEKT's 'E' (row 14 col 34) is itahdr. Verified cell
  by cell against `vice_empty_cram.bin`.
* ordlspr/upbordisp: `ptnsize` for track 0 lands on page $D9 (`dec vidzptr+1`
  runs before x=0): same bytes as VICE now.

### 18.5 Pixel diff vs ../sidwizard_re/shots (`python3 out/shot_png.py`)
Frame = 400x280 C64 pixels (the PNGs double the columns; text window origin
(40,36)). Palette fitted from the reference; the sprite and bar colours show
as 162 and 223 there (averages of palette 12/15 and 15/1), kept as measured.
* editor (02): **643 px**, all in four live areas: oscilloscope window
  (331..353,17..31; colour raster writes + SID OSC3 trace), the purple play
  bar in the right border (360..369,74..91), sprite 0 parked top right
  (363..366,16..31, cursor flasher), the PW meter bar (280..297,28..30; player
  value, the port presets 0). Outside them: **0** (110 glyph codes, 0 px off).
* startup (01): 14620 px; filer (04): 7313 px: the port's start-up menu and
  file dialog are the simplified Part-4 text layouts (no feature-tick grid,
  frame, raster fader, directory header) - known gaps 2 and 7, not font errors.
* menu / menu_theme / help / prompt have no reference shot.
Run: `zig run out/shot.zig 2> /tmp/f.txt; python3 out/shot_png.py /tmp/f.txt`
(writes ui_*.png 400x280, ui_*_win.png 320x200, ui_*_2x.png, diff_*.png).
