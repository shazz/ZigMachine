# fpga/case: the KESTREL / PEREGRINE case

The 3D-printed case of the console (VCF Montreal stand): measurements, the parametric OpenSCAD model,
exported STLs, renders and fit notes.

- `PLAN.md`: the measurement sheet and design approach; section 4 = the joint to the front parts, section 5 = Model v1.
- `kestrel_case.scad` + `lib/*.scad`: the model (every dimension a named Customizer variable, in `lib/params_ports.scad`).
- `stl/`: the 4 printed parts of OURS: `back_left`, `back_right`, `top_left`, `top_right`.
- `renders/`: `assembly.png` (3/4 view with ghosts), `top.png`, `back.png` (the port wall).
- `tools/`: `joint_analysis.py` (slices the reference STLs), `check_stl.py` (bed fit + manifold check).
- `layout_topview.py` / `.png`: the agreed top-view sketch the model follows.
- `photos/`: reference photos of the board and the hub (with a ruler).

One case for both boards: KESTREL (MicroPhase Z7-Lite 7010, `fpga/boards/microphase_z7_7010/`) and
PEREGRINE (the 7020 variant, `fpga/boards/microphase_z7_7020/`).

## What to print

The case = **the reference's FRONT parts, printed as is** (`front left.STL` and `front right.STL`, the MiSTer-wedge
keyboard tray Matt downloaded from Printables; third-party files, not in this repo: they live in
`prototypes/kestrel_case/`) + **our 4 parts** (`stl/*.stl`). Do not print the reference's own back and top
parts (`backleft/right-mister`, `topleft/right-mister`).

- Print standing as exported (z up, covers flat). Back parts 186.5 x 170 x 49, covers 186.5 x 176 x 4: a 190 x 180 bed.
- Screws and inserts (to confirm at the test fit): 2 x M3 per half for the front joint (holes d 3.15, 10 deep each
  side), 4 x M3 for the centre joint, 5 x M3 x 8..10 self-tapping per cover (counterbored heads), 4 x M3 heat-set
  inserts (d 4.2 x 6) + M3 x 6 for the board, 2 screws + nuts per panel connector (M3; USB-C may be M2.5), zip ties
  for the hub and the iCode.

## Render

```
openscad -o out.png --camera=186,230,20,50,0,200,900 --imgsize=1600,1200 -D show_covers=false kestrel_case.scad
openscad -D 'part="back_left"' -o stl/back_left.stl kestrel_case.scad          # one part (also the Customizer)
uv run --with numpy-stl --with numpy python tools/check_stl.py                   # bed + manifold
```

The assembly shows the reference front parts as ghosts only when `prototypes/kestrel_case/` exists (otherwise a
warning); `-D 'ref_dir="/abs/path/"'` points at another copy. `show_covers=false` hides the covers (they hide the
ghosts). A test strip of the port wall: `-D back_d=14 -D 'part="back_right"'`.
