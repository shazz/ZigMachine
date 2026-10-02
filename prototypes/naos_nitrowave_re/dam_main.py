"""F3's main loop ($4AC.. four phases), on dam_model.Part: the routines $924,
$9D8, $682, $6E0, $760 transcribed, then the frame driver and the oracle check.
    dam_main.py N   (RAM after N frames vs the oracle from the same snapshot)"""
import subprocess
import sys

from dam_model import FREEZE, PHASES, SNAP, Part


def frozen(p):
    return p.w(FREEZE) != 0


def columns(p):
    """$924: the scroller's nine column pointers ($30C6E) for the next VBL."""
    a0 = p.l(0x30C6A)
    if not frozen(p):
        a0 += 4
        if a0 == 0x30C6A:
            step_text(p)
        else:
            p.sl(0x30C6A, a0)
    a0 = p.l(0x30C6A)
    text = p.l(0x35734)
    for k in range(9):
        p.sl(0x30C6E + 4 * k, p.l(p.l(a0) + 4 * p.m[text + k]))


def step_text(p):
    """$970: four shifts done: the column 8 pixels on, and every third time a
    character on (the text wraps from $361B4 to $3577A)."""
    p.sl(0x30C6A, 0x30C5A)
    p.sl(0x30C98, p.l(0x30C98) - 8)
    n = p.w(0x30C96) - 1
    p.sw(0x30C96, n)
    if n:
        return
    p.sl(0x30C98, p.l(0x30C98) + 0x18)
    p.sw(0x30C96, 3)
    t = p.l(0x35734) + 1
    p.sl(0x35734, 0x3577A if t == 0x361B4 else t)


def scroll_wave(p):
    """$9D8: the scroller's place ($30C92) and the clear's ($30C9C)."""
    a0 = p.l(0x30E7C)
    d0, d1 = p.w(a0), p.w(a0 + 2)
    a0 += 4
    if frozen(p):
        a0 -= 4
    if a0 == 0x30E7C:
        a0 = 0x30CA0
    p.sl(0x30E7C, a0)
    p.sl(0x30C92, p.l(0x30C92) + d0)
    p.sl(0x30C9C, d1 + p.l(0x361F4) + 0xA08E)


def band_top(p):
    """$682: the top band's source (a6) and, each time its list wraps, the
    next pair of line routines."""
    a0 = p.l(0x31010)
    if not frozen(p):
        a0 += 4
        if a0 == 0x31010:
            p.sl(0x31010, 0x30FF0)
            p.a6 = p.l(0x30FF0)
            q = p.l(0x30F68)
            p.sl(0x30F6C, p.l(q))
            p.sl(0x30F70, p.l(q + 4))
            q += 8
            p.sl(0x30F68, 0x30E80 if q == 0x30F68 else q)
            return
        p.sl(0x31010, a0)
    p.a6 = p.l(a0)


def band_bottom(p):
    """$6E0: the same for the bottom band ($31028, routines $30FE8/$30FEC)."""
    a0 = p.l(0x31024)
    if not frozen(p):
        a0 += 4
        if a0 == 0x31024:
            p.sl(0x31024, 0x31014)
            p.sl(0x31028, p.l(0x31014))
            q = p.l(0x30FE4)
            p.sl(0x30FE8, p.l(q))
            p.sl(0x30FEC, p.l(q + 4))
            q += 8
            p.sl(0x30FE4, 0x30F74 if q == 0x30FE4 else q)
            return
        p.sl(0x31024, a0)
    p.sl(0x31028, p.l(a0))


# $760: the logo's distortion. States 2 and 3 walk a table 8 bytes a frame
# (end, restart, next state, its count); state $64 plays the list $35660.
WALKS = {2: (0x31628, 0x31280, 3, 0xC), 3: (0x31A30, 0x31888, 5, None)}
P_TAB, P_N, P_N2, P_STATE, P_LIST = 0x35730, 0x31030, 0x31032, 0x31034, 0x3572C


def logo_wave(p):
    """-> a4 for the next VBL."""
    while True:
        st = p.w(P_STATE)
        if st == 0x64:
            return logo_list(p)
        if st == 1:
            if not frozen(p):
                n = p.w(P_N) - 1
                p.sw(P_N, n)
                if n == 0:
                    p.sw(P_N, 0xA)
                    p.sw(P_STATE, 2)
                    continue
            return p.l(P_TAB)
        if st in WALKS:
            end, restart, nxt, count = WALKS[st]
            if not frozen(p):
                p.sl(P_TAB, p.l(P_TAB) + 8)
                if p.l(P_TAB) == end:
                    n = p.w(P_N) - 1
                    p.sw(P_N, n)
                    if n == 0:
                        if count is not None:
                            p.sw(P_N, count)
                        p.sw(P_STATE, nxt)
                        continue
                    p.sl(P_TAB, restart)
            return p.l(P_TAB)
        if st == 5:
            if not frozen(p):
                p.sl(P_TAB, p.l(P_TAB) + 8)
                if p.l(P_TAB) == 0x31BE0:
                    p.sw(P_N, 0x64)
                    p.sw(P_STATE, 6)
                    return logo_hold(p)
            return p.l(P_TAB)
        return logo_hold(p)


def logo_hold(p):
    """$884: state 6 holds the last line for $64 frames, then the list."""
    p.sl(P_TAB, 0x31BE0)
    if not frozen(p):
        n = p.w(P_N) - 1
        p.sw(P_N, n)
        if n == 0:
            p.sw(P_N, 0x12C)
            p.sw(P_STATE, 0x64)
            p.sw(P_N2, 0xF)
            return logo_list(p)  # $8BE runs on into $8C6
    return p.l(P_TAB)


def logo_list(p):
    """$8C6: entries (pointer, frames) of $35660..$3572C, $F rounds, then $746."""
    if not frozen(p):
        n = p.w(P_N) - 1
        p.sw(P_N, n)
        if n == 0:
            q = p.l(P_LIST) + 6
            if q == 0x3572C:
                q = 0x35660
                p.sl(P_LIST, q)
                n2 = p.w(P_N2) - 1
                p.sw(P_N2, n2)
                if n2 == 0:
                    p.sl(P_TAB, 0x31038)
                    p.sw(P_STATE, 1)
                    p.sw(P_N, 0x12C)
                    return logo_wave(p)
            p.sl(P_LIST, q)
            p.sw(P_N, p.w(q + 4))
            return p.l(q)
    return p.l(p.l(P_LIST))


def frame(p):
    """One VBL and the main loop's phase after it. -> the screen shown while
    the VBL ran."""
    shown = p.shown
    p.vbl()
    draw, show, a5, bottom = PHASES[p.phase]
    columns(p)
    p.sl(0x361F4, draw)
    p.sl(0x30C92, draw + p.l(0x30C98))
    scroll_wave(p)
    p.shown = show
    p.a5 = a5
    band_top(p)
    p.sl(0x3102C, bottom)
    band_bottom(p)
    p.a4 = logo_wave(p)
    if not (p.phase == 0 and frozen(p)):
        p.phase = (p.phase + 1) % 4
    return shown


if __name__ == '__main__':
    N = int(sys.argv[1])
    subprocess.run(['./m68loop', SNAP, '4ac', str(N), 'dumps/od3', str(N)], check=True)
    p = Part()
    for _ in range(N):
        frame(p)
    ref = open(f'dumps/od3.{N}', 'rb').read()
    bad = [i for i in range(0x2400, 0x7A000) if p.m[i] != ref[i]]  # below: the music replay's state
    print(N, 'frames:', len(bad), 'bytes differ', [hex(i) for i in bad[:12]])
