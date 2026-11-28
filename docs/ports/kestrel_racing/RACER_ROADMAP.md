# Kestrel Racing: what is left after v1

Status 28 Nov 2026: Matt's board test of RACER OPT / RACER OPT 32X: "running well overall, around 30 fps... for a v1, this
is good". Work paused for a bigger project; this file holds what remains. Row in docs/project/ROADMAP.md: R82.

## Polish (Matt, 28 Nov)

- **Title screen**: needs polishing (our own look, not Sega's).
- **Track (course) select**: needs polishing; the turning height-field model, outlines and records are there (BATCH.md).
- Car select: same pass as the course select.

## Performance (OPTIMIZE.md has the measurements)

Board, race with the AI pilot, R 8: 32X courses 24-30.5 fps, our tracks 41-56 (bench 60). The 8 cars cost ~1.4 Mc of a
DXBAY race; with the cars hidden the floor is 33 fps.

- **Cars stay real 3D** (Matt, 28 Nov): no pre-rendered car sprites.
- **Shadow darken op**: a CHISEL op that darkens the destination itself (~4 ms of a DXBAY frame) is on the PEREGRINE
  list (ROADMAP R85); no KESTREL change.
- **Face merge** (branch perf/racer-facemerge, not merged): coplanar same-colour faces in the 32X importer. Only
  0.8-2.7 % of the faces merge (the 32X meshes shade adjacent facets in different entries), ~0.1-0.2 fps; a RACER MERGE
  32X card for Matt to compare on the board. Merge only if the board shows a gain.
- **CITY flyby**: the OSD reads ~58 fps but glass reports 31; something outside the cart waits there. Not investigated.
- Cheaper far cars (keys - = ;) buy ~0.6 fps and change the picture: not recommended.

## Open from earlier milestones

- Track Kit licence (TRACK_KIT.md, Q2).
- Records are RAM-only until a save file exists (M3.md, Q6).

## Rules that stay

LOCAL ONLY, never committed or shared: the 32X ROM and everything derived from it (courses, cars, panoramas), the VGM
music rips. Only importer code and synthetic test data are committed. The public cart races our tracks and the GT.
