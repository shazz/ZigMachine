| cart | fps | frame_ms | frames | missed | bard | player | state | err | song |
|---|---|---|---|---|---|---|---|---|---|
| demo-leonard.zmd | 59.4 | 16.8 | 292 | 3 | 12/26 | BARD:SNDH_68k | running | - | sos.sndh |
| demo-automation442.zmd | 30.1 | 33.1 | 148 | 147 | 0/21 | BARD:SNDH_68k | running | - | Jinks.sndh |
| demo-deltaforce.zmd | 40.3 | 24.8 | 198 | 97 | 0/22 | BARD:SNDH_68k | running | - | renegade.sndh |
| demo-stcs.zmd | 31.3 | 31.9 | 154 | 141 | 0/24 | BARD:SNDH_68k | running | - | thrust.sndh |
| demo-union_l16.zmd | 30.3 | 32.9 | 149 | 146 | 2/2 | BARD:SNDH_68k | running | - | union/level_16.sndh |
| demo-ancool.zmd | 30.1 | 33.1 | 148 | 147 | 17/23 | BARD:SNDH_68k | running | - | sowatt_an_bass.sndh |
| demo-fallen_angels.zmd | 40.3 | 24.8 | 198 | 97 | 7/11 | BARD:SNDH_68k | running | - | count_zero_2.sndh |
| demo-union_main.zmd | 22.1 | 45.0 | 109 | 186 | 12/17 | BARD:SNDH_68k | running | - | union/sharpness_buzztone.sndh |
| demo-dbug.zmd | 25.4 | 39.3 | 125 | 170 | 0/27 | BARD:SNDH_n#14 | running | - | crystallized.sndh |

FRESCO probe (sys cycles per frame; /pass: per BG/PLANE/MIX pass; comp/pass in sys cycles):

| cart | fps | frame_c | cart_c | seq_c | passes | seq/pass | painted/pass | ready/pass | comp/pass | hbl | plan | swap | underrun |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| demo-leonard.zmd | 59.4 | 1649372 | 717467 | 921004 | 840 | 1096 | 0 | 867 | 973 | 0 | 0 | 12982 | boot |
| demo-automation442.zmd | 30.1 | 3307174 | 144376 | 3152891 | 560 | 5630 | 1032 | 1707 | 3107 | 87318 | 0 | 1348662 | boot |
| demo-deltaforce.zmd | 40.3 | 2477594 | 183610 | 2283287 | 560 | 4077 | 855 | 1644 | 2839 | 76629 | 0 | 628469 | boot |
| demo-stcs.zmd | 31.3 | 3202631 | 240300 | 2951262 | 840 | 3513 | 726 | 1056 | 2259 | 265093 | 0 | 921930 | boot |
| demo-union_l16.zmd | 30.3 | 3306002 | 793418 | 2499808 | 560 | 4464 | 1031 | 1598 | 3107 | 150282 | 0 | 692207 | boot |
| demo-ancool.zmd | 30.1 | 3306083 | 634153 | 2659860 | 840 | 3166 | 385 | 1411 | 2055 | 90675 | 0 | 840086 | boot |
| demo-fallen_angels.zmd | 40.3 | 2477177 | 491765 | 1973148 | 560 | 3523 | 273 | 1919 | 2526 | 68867 | 0 | 492733 | boot |
| demo-union_main.zmd | 22.1 | 4370889 | 1563007 | 2793966 | 840 | 3326 | 1135 | 1676 | 3213 | 163127 | 0 | 64 | boot |
| demo-dbug.zmd | 25.4 | 3898155 | 2353613 | 1531710 | 560 | 2735 | 370 | 1849 | 2617 | 105229 | 0 | 69 | boot |

Row costs at boot (demo-leonard.zmd; span sys / comp clocks): cal_mix1=1746/2139, cal_mix2=2150/2653, cal_fill1=2550/3147, cal_fill2=2870/3554
