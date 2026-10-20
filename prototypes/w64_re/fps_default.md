| cart | fps | frame_ms | frames | missed | bard | player | state | err | song |
|---|---|---|---|---|---|---|---|---|---|
| demo-automation442.zmd | 60.2 | 16.5 | 296 | 0 | 0/21 | BARD:SNDH_68k | running | - | Jinks.sndh |
| demo-deltaforce.zmd | 60.2 | 16.5 | 296 | 0 | 0/22 | BARD:SNDH_68k | running | - | renegade.sndh |
| demo-stcs.zmd | 48.2 | 20.7 | 237 | 58 | 11/24 | BARD:SNDH_68k | running | - | thrust.sndh |
| demo-leonard.zmd | 59.4 | 16.8 | 292 | 3 | 13/26 | BARD:SNDH_68k | running | - | sos.sndh |

FRESCO probe (sys cycles per frame; /pass: per BG/PLANE/MIX pass; comp/pass in sys cycles):

| cart | fps | frame_c | cart_c | seq_c | passes | seq/pass | painted/pass | ready/pass | comp/pass | hbl | plan | swap | underrun |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| demo-automation442.zmd | 60.2 | 1649172 | 148505 | 1490655 | 560 | 2662 | 980 | 920 | 2264 | 87301 | 0 | 158123 | boot |
| demo-deltaforce.zmd | 60.2 | 1648785 | 183763 | 1454304 | 560 | 2597 | 816 | 884 | 2043 | 76727 | 0 | 244547 | boot |
| demo-stcs.zmd | 48.2 | 2063173 | 249902 | 1802212 | 840 | 2145 | 695 | 495 | 1615 | 262908 | 16753 | 257081 | boot |
| demo-leonard.zmd | 59.4 | 1649452 | 718265 | 920219 | 840 | 1095 | 0 | 721 | 826 | 0 | 0 | 135472 | boot |

Row costs at boot (demo-automation442.zmd; span sys / comp clocks): cal_mix1=1307/1592, cal_mix2=1693/2079, cal_fill1=1582/1939, cal_fill2=2021/2488
