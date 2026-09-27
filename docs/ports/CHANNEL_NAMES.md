# Channel display names — review

Renames applied to `apps/zig/scenes/catalog.zig`'s `.name` field, and why. One
row per catalog entry. `len` is the new name's character count (hard cap: 22,
enforced by `tools/channels.py`'s `MAX_NAME_LEN` check — see "Length limit"
below).

## Renamed

| tag | old name | new name | len | evidence |
|---|---|---|---|---|
| ancool | ANCOOL | AN COOL | 7 | `ancool.zig:40` scrolltext: `"-AN COOL- IS BACK..."` — the group spells its own name with a space |
| bladerunners | BLADERUNNERS | BLADERUNNERS DUNGEON | 20 | `bladerunners.zig:34` scrolltext: `"WELCOME TO 'DUNGEON MASTER'...CRACKED FOR THE BLADE RUNNERS"` |
| dbug | DBUG | D-BUG | 5 | `dbug_credits.zig:2` header: "D-BUG credit panel"; group's own spelling has the hyphen. (No production title found in-repo for this screen — "AUTODBUG" was considered but dropped: not confirmed anywhere in the repo, only in an unrelated prior-session memory note, so it's not repo evidence.) |
| deltaforce | DELTA FORCE | DELTAFORCE TESTDRIVE | 20 | `deltaforce.zig:32` scrolltext: `"TESTDRIVE WAS CRACKED BY CHAOS, INC. OF THE DELTAFORCE CRACKING GROUP"` |
| deltaforce2 | DELTA FORCE 2 | DELTAFORCE JINXSTER | 19 | `deltaforce2.zig:35` scrolltext: `"JINXSTER - CRACKED...BY CHAOS, INC. OF THE DELTAFORCE CRACKING GROUP"` |
| equinox | EQUINOX | EQUINOX RVF HONDA | 17 | `equinox/scrolltext.txt`: `"EQUINOX PRESENTS RVF HONDA CRACKED BY ILLEGAL"` |
| fallen_angels | FALLEN ANGELS | F.ANGELS GOLDEN AXE | 19 | `fallen_angels.zig:39` scrolltext: `"THE EMPIRE PRESENTS : GOLDEN AXE...FROM THE FALLEN ANGELS"` |
| ics | ICS | ICS BUMPY'S | 11 | `ics.zig:36` scrolltext: `"ICS PRESENTS YOU: BUMPY'S GAME CRACKED BY THE THREAT...FOR I.C.S."` |
| leonard | LEONARD | OXYGENE 312 SPRITES | 19 | `leonard.zig:36` scrolltext: `"...I NEVER THOUGH I COULD DISPLAY 312 SPRITES ONE YEAR AGO...LEONARD/OXYGENE, 17.03.2005"` — the record this screen boasts of, over the bare coder/group signature ("LEONARD/OXYGENE") alone |
| stcs | STCS | STCS STARGOOSE | 14 | `stcs.zig:34` scrolltext: `"THE S.T.C.S. STRIKES BACK...CALLED -- STARGOOSE --"` |
| tex | TEX | TEX - THE UNION | 15 | `tex.zig:1-2` header: `"TEX — 'The Exceptions' crack screen for The Union"`; scrolltext: `"CRACKED BY HOWDY FROM THE EXCEPTIONS MEMBER OF THE UNION"` — no specific game named in this screen's own scroll |
| noextra | NOEXTRA | NOEXTRA DHS MEGADEMO | 20 | `noextra.zig:131-137` scrolltext: `"WELCOME ON THE GREAT COMPILATION OF D.H.S.: THE ST DEMOSCREEN COMPETITION...PART OF THE DHS MEGADEMO 2005"` |
| replicants_dd2 | REPLICANTS DD2 | REPS DOUBLE DRAGON 2 | 20 | `replicants_dd2.zig:134-138` scrolltext: `"REPLICANTS PRESENT DOUBLE DRAGON II"` |
| supplex_fs2 | SUPPLEX FS2 | SUPPLEX FLIGHT SIM 2 | 20 | `supplex_fs2.zig:123-126` scrolltext: `"SUPPLEX IS PROUD TO PRESENT...FLIGHT SIMULATOR II NEW DATA DISK"` |
| ulm_spoon_distorter | ULM SPOON DISTORTER | ULM DARK SIDE SPOON | 19 | `ulm_spoon_distorter.zig:1-3` header: `ULM — "Parallax Distorter", Gunstick's fullscreen screen from THE DARK SIDE OF THE SPOON` — the production (whole demo) is "The Dark Side of the Spoon"; "Parallax Distorter" is this one screen's effect name within it |
| cuddly_starwars | CUDDLY STARWARS | TCB STARWARS SCROLLER | 21 | `cuddly_starwars.zig:1-2` header: `THE CAREBEARS — "The Starwars Scroller", The Cuddly Demos`; renamed to the TCB short tag already used consistently elsewhere in this catalog (tcb_spreadpoint, tcb_weirddream, tcb_colorshock) rather than spelling out CAREBEARS |
| stniccc | STNICCC 2000 | OXYGENE STNICCC 2000 | 20 | `stniccc.zig:1-2` header: "the flat-shaded flight from Oxygene's Atari ST demo (2000)" — added the group; "STNICCC 2000" itself is the demo's own established title, kept verbatim |
| tex_neoshow | TEX NEO SHOW | TEX SUPER NEO SHOW | 18 | `tex_neoshow.zig` header: `The Exceptions (TEX) — "Super Neo Demo Show"` — old name dropped "SUPER" |
| c-screen34 | REPS FRED (C) | MAD VISION FRED (C) | 19 | `apps/c/scenes/screen34.c:3-4`: `"MAD VISION's intro for MAXI's crack of 'Fred'"` — **the old name misattributed the group**: it said REPS (Replicants), the real group is Mad Vision |
| elite_snooker | ELITE SNOOKER | ELITE JIMMY WHITE | 17 | `elite_snooker.zig:1-2` header: `ELITE — "Jimmy White Snooker" crack intro` — old name used the genre, not the game's title |
| tcb_colorshock | TCB COLORSHOCK | TCB COLORSHOCK 2 | 16 | `tcb_colorshock.zig:2` header: `THE CAREBEARS — COLORSHOCK 2, from The Cuddly Demos` — old name dropped the "2" |
| tsl_hybridglenz | SILENTS HYBRID GLENZ | TSL HYBRID GLENZ | 16 | `tsl_hybridglenz.zig:1-2` header: `THE SILENTS — "HYBRID GLENZ" (1993)`; renamed to the TSL short tag, matching the TCB/RNO/ULM/TEX/DHS convention used throughout this catalog |
| stcs_css3 | STCS 3RD CSS CONVENTION | STCS DEMONIAQ | 13 | `stcs_css3.zig:1-3` header: `ST COMPUTER SERVICE (STCS) — "DEMONIAQ", the Tsunoo Rhilty intro for the 3rd CSS Convention` — the production's own title is DEMONIAQ; "3rd CSS Convention" is the event it was made for, and the old name (23 chars) was over the limit anyway |
| tcb_weirddream | TCB WEIRD DREAM | TCB/REPS WEIRD DREAM | 20 | `tcb_weirddream.zig:2` header: `THE CAREBEARS + THE REPLICANTS — "WEIRD DREAM" crack intro` — old name credited only one of the two groups |
| gen4_3615 | ULM 3615 GEN4 | THE FATE 3615 GEN4 | 18 | `gen4_3615.zig:1-6`: `ULM (Unlimited Matricks) — the 3615 GEN4 contest screen, by The Fate` / `"code, scrolltext and music by The Fate: all theirs"` — **the old name misattributed authorship**: ULM ran the contest (and their logo cameos in the screen), but The Fate made it |
| replicants (tag) | REPS OLD | REPS OLD GARFIELD | 17 | this is the pre-CODEF duplicate of `replicants_garfield` — its scrolltext (`replicants.zig:29`) is the same Garfield crack text, near word-for-word. It is deliberately hidden from the public channel list (`tools/channels.py` EXCLUDE comment: "kept only for side-by-side comparison"), so "REPS OLD" alone no longer said *what* it's an old version of; this makes it explicit for anyone reading the dev-only menu list |

## Left unchanged (already accurate, or evidence too thin to improve)

| tag | name | why unchanged |
|---|---|---|
| union_intro, union_main, music, blitter, scroll, obj, gem, st_replay, fullscreen, badflicker, maxi, medium_overscan, res_switch, shapes, stream, mandelbrot, tutorial, mpp_truecolor, scrolllab, polkadots | (various) | ZigMachine's own tech demos / system screens, already descriptive; no group/production to attribute |
| empire | EMPIRE | its own scrolltext (`empire.zig:40`) names no specific cracked game ("A NEW LITTLE INTRO"); nothing to add without inventing |
| replicants_garfield | REPLICANTS GARFIELD | already GROUP + game title, matches `replicants_garfield.zig:1-2` exactly |
| replicants_kickoff2 | REPLICANTS KICK OFF 2 | already GROUP + game title, matches `replicants_kickoff2.zig:1-2` |
| dyno_paradis3 | DYNO PARADIS3 | matches `dyno_paradis3.zig` header: `Dyno — "ParaDis3 - Parallax Distorter"` |
| rust-v8_populous | V8 POPULOUS (RUST) | matches `apps/rust/scenes/v8_populous.rs:3`: `THE FABULOUS V8's intro for their crack of "Populous"` |
| big_demo | TEX B.I.G. DEMO | matches `big_demo.zig:1-2`: `THE B.I.G. DEMO — The Exceptions (TEX), 1988` |
| tlb_spoon | TLB TWIDDLE DEMO | matches `tlb_spoon.zig:1-2`: `THE LOST BOYS — "THE TWIDDLE DEMO", from the ULM Megademo` |
| vex | VEX 2025 GTA VI | matches `vex.zig:1-2`: `VEX 2025 — "vEctRoniX presents Grand Theft Auto VI, Atari ST/E"` |
| replicants_emlyn | REPLICANTS EMLYN | matches `replicants_emlyn.zig:1-2`: `THE REPLICANTS — "Emlyn Hughes International Soccer" crack intro` |
| elite_cfsr | ELITE CHALLENGE FOOT | matches `elite_cfsr.zig:1-2`: `ELITE — the crack intro for "Challenge Foot Senior"` (abbreviated to fit) |
| rno_sodium | RNO SODIUM | matches `rno_sodium.zig:1-2`: `SODIUM — RNO (Rave Network Overscan)` |
| rno_natrium | RNO NATRIUM | matches `rno_natrium.zig:1-2`: `RNO (Rave Network Overscan) — NATRIUM` |
| dhs_0pxl0reg | DHS 0PIXELS 0REGRETS | matches `dhs_0pxl0reg.zig:1-4`: `DHS (Dead Hackers Society) — "(n)0 PIXELS (n)0 REGRETS"` exactly |
| trsi_transarctica | TRSI TRANSARCTICA | matches header: `TRSI -- TRANSARCTICA cracktro, Atari Falcon030, 1993` |
| c-fujiboink | FUJIBOINK (C) | `apps/c/scenes/fujiboink.c:2`: `"FujiBoink! Written by Xanth Park..."` — a standalone program, not a demo group; the `(C)` marks this as the C-language port (same convention as `c-screen34`) |
| north_south | NORTH & SOUTH BATTLE | matches `north_south.zig:2`: `NORTH & SOUTH ("Nord et Sud", Infogrames 1989): the BATTLE, playable` |
| joust | JOUST | matches `joust.zig:2`: `JOUST -- Atari Corp. 1986` — game title |
| tcb_spreadpoint | TCB SPREADPOINT | matches `tcb_spreadpoint.zig:2`: `THE CAREBEARS -- THE SPREADPOINT DEMO, from The Cuddly Demos` |
| swedish_newyear | SWEDISH NEW YEAR | `swedish_newyear.zig:1-5` credits four groups (SYNC, AN COOL, TCB, OMEGA) for one multi-part disk — no single group fits, and the production's own title is the only accurate short name |
| rick_dangerous | RICK DANGEROUS | matches `rick_dangerous.zig:2`: `RICK DANGEROUS -- Core Design / Firebird 1989` — game title |
| union_intro_screen | UNION DEMO | **must not change**: `apps/union_demo_doors_check.mjs:91` hardcodes a regex match on `.name = "UNION DEMO"` to find this entry's tag; the name is already accurate (the demo's opening splash) |
| automation442 | AUTOMATION 442 | matches `automation442.zig` header (AUTOMATION disk-mag issue 442, part A); already short and accurate |

## Length limit

Matt's constraint (from a Select OSD screenshot, `docs/css/cart-select.css`
`.cs_title`): **hard max 22 characters**, including spaces/punctuation. Enforced
by a new check in `tools/channels.py` (`MAX_NAME_LEN = 22`, checked in
`entries()`, so it fails both a plain run and `--check`).

Other places the name is shown, checked and confirmed to have no smaller
budget:
- **Menu cart** (`apps/zig/scenes/menu.zig`): two columns, 152px apart, name
  drawn at `x + 12` in the 8x8 system font (`libs/zig/zigos.zig` `printText`,
  `SYSTEM_FONT_WIDTH = 8`). `blitGlyphs` clips text to the framebuffer edge
  (`if (gx >= w) return`) rather than wrapping, so an overlong name is only
  ever *cut*, never corrupts the layout — but a name much longer than ~17-18
  characters in the left column can visually run into the right column's
  entry on the same row (this is pre-existing: names up to 23 characters were
  already in the catalog before this change, e.g. the old `STCS 3RD CSS
  CONVENTION`). The 22-char cap does not fully eliminate that theoretical
  overlap, but it does not make it any worse than what already shipped, and
  fixing the menu's per-column clipping is a separate, pre-existing issue
  outside this task's scope.
- **VHS name card** (`docs/cart-osd.js`) and **Select OSD** (`docs/cart-select.js`
  `.cs_title`): both plain browser text with `overflow: hidden; text-overflow:
  ellipsis` (Select) or no fixed width at all (name card) — 22 characters
  fits comfortably in both.
- **Font glyph set**: verified every character used (`A-Z 0-9 space - . ' & ( ) / !`)
  has a non-empty glyph in `libs/zig/assets/fonts/system_font_atari_1bit.raw`
  (checked by decoding the raw 8x8 1-bit font and confirming each glyph has
  "ink" pixels).

## Pre-existing, out of scope

`tools/channels.py`'s own module docstring says it writes `docs/channels.json`
and `docs/cart-names.json`; it only writes the former (`docs/cart-names.json`
does not exist in the repo). This predates this change and is unrelated to the
renaming — left as-is.
