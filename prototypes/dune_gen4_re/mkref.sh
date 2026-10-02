#!/bin/sh
# mkref.sh: rebuild apps/dune_gen4_ref.bin.br from the Hatari runs, frames dumped
# beforehand with `python3 avi2png.py hatari/refN.avi /dev/shm/refN 1`.
# Group offsets are each run's traced VBLs (trace.py): see NOTES.md.
cd "$(dirname "$0")" || exit 1
python3 mkref.py ../../apps/dune_gen4_ref.bin.br \
  /dev/shm/ref2:1220:intro bounce-first:1248 bounce-top:1280 bounce-bottom:1313 bounce-turn:1314 \
    bounce-late:1470 prep:1478 fade-s2:1486 fade-s4:1492 fade-s7:1503 logo-hold:1520 main-first:1657 \
    main-2:1658 main-9:1665 main-44:1700 main-144:1800 main-344:2000 main-443:2099 \
  /dev/shm/ref4:2324:title title-40:2364 title-150:2474 \
  /dev/shm/ref4:2776:menu1 menu1-30:2806 menu1-31:2807 menu1-74:2850 menu1-224:3000 menu1-304:3080 \
  /dev/shm/ref4:3253:black1 black1-77:3330 black1-78:3331 black1-197:3450 black1-447:3700 \
  /dev/shm/ref4:4086:menu2 menu2-30:4116 menu2-31:4117 menu2-200:4286 \
  /dev/shm/ref4:4594:black2 black2-77:4671 black2-206:4800 black2-406:5000 \
  /dev/shm/ref4:5230:menu3 menu3-30:5260 menu3-170:5400 menu3-369:5599 \
  /dev/shm/ref5:2710:hades1 hades1-17:2727 hades1-18:2728 hades1-19:2729 hades1-50:2760 \
    hades1-290:3000 hades1-1290:4000 hades1-1720:4430 \
  /dev/shm/ref5:4720:hades2 hades2-18:4738 hades2-280:5000 hades2-730:5450 \
  /dev/shm/ref5:5631:menu5 menu5-30:5661 menu5-500:6131
