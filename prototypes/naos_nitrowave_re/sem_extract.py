"""Read the VBL program back as (column, row) draw records and check it is the
regular shape menu_sem.py assumes: column c, row r writes the screen at
+16 + 8c + 230r, reads gfx/mask at +160r, and takes plane 2 from the gfx's
plane-3 word on some rows (move.l $..4(a4),d2 then or.w d2). Prints those rows."""
from vbl68k import menu_vbl_program

prog = menu_vbl_program()
col = -1
recs = {}
cur_d2_long = None
for m, ops in prog:
    if m == 'movea.l' and ops[0] == '(a2)+':
        col += 1
    elif m in ('move.w', 'move.l') and ops[1] == 'd2' and '(a4)' in ops[0]:
        off = int(ops[0].split('(')[0].lstrip('$') or '0', 16)
        cur_d2_long = (m == 'move.l', off)
    elif m == 'or.w':
        dst = int(ops[1].split('(')[0].lstrip('$') or '0', 16)
        r = (dst - 4) // 230
        assert (dst - 4) % 230 == 0, ops
        is_long, off = cur_d2_long
        assert off == 160 * r + 4, (col, r, off)
        recs[(col, r)] = is_long
cols = sorted({c for c, _ in recs})
rows = sorted({r for _, r in recs})
print('columns', cols[0], '..', cols[-1], 'rows', rows[0], '..', rows[-1], 'records', len(recs))
plane3 = sorted({r for (c, r), v in recs.items() if v})
print('rows taking plane 2 from the plane-3 word:', plane3)
print('same rows in every column:', all(recs[(c, r)] == (r in plane3) for c, r in recs))
