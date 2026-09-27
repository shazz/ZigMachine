#!/usr/bin/env python3
"""The lockstep fixture of apps/rick_dangerous_headless.mjs, from the reference model.

    python3 tools/rick_dangerous/make_fixture.py [--calls] [--out FILE] DUMP [DUMP ...]

For each harness dump (prototypes/rick_re/harness/dumps/<DUMP>, gitignored), this runs the
reference model (prototypes/rick_re/model, verify.py --whole: 0 oracle answers, every dump byte
for byte) from the dump's first key frame to its last complete frame, and records:

  init    the first key frame: the model's state over harness/regions.json (zlib, base64), the
          palette, the video base
  tape    the OUTSIDE WORLD, exactly as the model takes it from the harness, as a flat int list:
            per call:  k, n, n x (address, byte)   the ACIA / Timer A bytes the harness held at
                                                   the call's entry, where they differ from the
                                                   model's own (verify.py replays them)
                       4 event lists (joy_events, key_events in cycles since the call started;
                       joy_vbls, key_vbls in VBLs): count, count x (time, byte)
                       moved: the VBLs the harness took INSIDE the call that the model takes at
                       its end (level 4's heavy frames, FINAL.md 1)
  irqs    per VBL interrupt the model takes (in order): n, n x (address, byte), the Timer A
          bytes the harness held when that interrupt fired (the audio clock), where they differ
  frames  per frame: the CRC-32 of the snapshot regions + the video base + the 16 colour
          registers, the VBLs the frame took, and the play_sound requests (id << 8 | d1)

The cart replays the tape and must reproduce every frame's CRC. --calls adds the CRC after
every call (a development aid: it names the first call that differs).
"""
import argparse
import base64
import gzip
import json
import os
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RE = os.environ.get('RICK_RE', os.path.join('/home/matt/projects/ZigMachine/prototypes/rick_re'))
sys.path.insert(0, os.path.join(RE, 'model'))
sys.path.insert(0, os.path.join(RE, 'harness'))

import d_player                                                       # noqa: E402
import rick_model as rm                                               # noqa: E402
import verify                                                         # noqa: E402
from core import FrameInput                                           # noqa: E402
from dump import load_regions                                         # noqa: E402
from dumpio import INPUT_BYTES, TIMERA_BYTES, Oracle, Reader, snap_pos, snapshot  # noqa: E402
from state import GameState                                           # noqa: E402

EVENTS = ('joy_events', 'key_events', 'joy_vbls', 'key_vbls')
# harness/regions.json: every byte the game writes in its loop. Each dump holds the list it was made
# with (older ones lack the live palette and the erase source); all of them are inside this one, so
# the fixture's snapshots and CRCs use it, filled from the model (entry image + the dump's snapshot).
REGIONS = load_regions()


def dump_dir(name):
    """harness/dumps/NAME, or package D's model/d_dumps/NAME (d_menu, d_hiscore, d_hiscore2)"""
    p = os.path.join(RE, 'harness', 'dumps', name)
    return p if os.path.isdir(p) else os.path.join(RE, 'model', 'd_dumps', name)


class SoundLog(list):
    """st.sounds: d_sound.play_sound appends [id, d1] before it touches any state, so the drop
    rule's inputs are read here: an entry is id << 8 | d1, + $10000 dropped (an sfx / digi while
    a tune plays or a digi is busy), + $20000 sfx_alt (the channel an sfx with d1 = 0 takes),
    + $40000 requested by the VBL tick itself (a looping tune restarting), not by the game"""

    def __init__(self, st):
        super().__init__()
        self.st = st
        self.in_tick = False

    def append(self, rec):
        st, (n, d1) = self.st, rec
        kind = st.rw(0x3498A + ((n & 0xFF) << 3))
        mode = st.rb(0x34A84)
        dropped = kind != 0 and (mode == 1 or bool(mode & 0x80))
        super().append(((n & 0xFF) << 8) | (d1 & 0xFF) | (dropped << 16)
                       | ((st.rb(0x34A85) & 1) << 17) | (self.in_tick << 18))


def state_crc(st, regions):
    c = zlib.crc32(snapshot(st.mem, regions))
    c = zlib.crc32(struct.pack('>I', st.vbase & 0xFFFFFFFF), c)
    return zlib.crc32(struct.pack('>16H', *[p & 0xFFFF for p in st.pal]), c)


def run(name, per_call):
    r = Reader(dump_dir(name))
    orc = Oracle(r)
    keys = r.keys()
    st = GameState()
    drv = rm.attach(st, rm.Driver(orc))
    verify.load(st, r, keys[0])
    init = dict(snap=base64.b64encode(zlib.compress(snapshot(st.mem, REGIONS), 9)).decode(),
                pal=list(r.recs[keys[0]]['pal']), vbase=r.recs[keys[0]]['vbase'])
    tape, irqs, frames = [], [], []
    orig_run_call = rm.run_call
    orig_tick = d_player.tick

    def tick(s):
        s.sounds.in_tick = True
        try:
            orig_tick(s)
        finally:
            s.sounds.in_tick = False
    d_player.tick = tick
    orig_take = orc.take_irq

    def take_irq(s):
        before = [s.mem[a] for a in TIMERA_BYTES]
        ok = orig_take(s)
        diff = [(a, s.mem[a]) for a, b in zip(TIMERA_BYTES, before) if s.mem[a] != b]
        irqs.append(len(diff))
        for a, v in diff:
            irqs.extend((a, v))
        return ok
    orc.take_irq = take_irq

    def run_call(s, k, inp):
        at = inp.at_call.get(k, [])
        diff = [(a, v) for a, v in at if s.mem[a] != v]
        # the entry bytes are applied by run_call itself; record them against the state now
        rec = [k, len(diff)]
        for a, v in diff:
            rec.extend((a, v))
        ci = inp.for_call(k)
        for n in EVENTS:
            ev = getattr(ci, n) or []
            rec.append(len(ev))
            for t, b in ev:
                rec.extend((t, b))
        moved0 = drv.moved_irqs
        pos = len(tape)
        tape.extend(rec)
        tape.append(0)                          # moved, patched below
        try:
            return orig_run_call(s, k, inp)
        finally:
            tape[pos + len(rec)] = drv.moved_irqs - moved0
            if per_call:
                tape.append(state_crc(s, REGIONS))
    rm.run_call = run_call
    n_ok = 0
    try:
        for ki in keys:
            f = r.recs[ki]['frame']
            orc.select(f)
            at, evs = {}, {}
            for i in orc.calls:
                snap = r.snapshot(r.pre_of(i))
                k = r.recs[i]['call']
                at[k] = [(a, snap[snap_pos(a, r.regions)]) for a in INPUT_BYTES + TIMERA_BYTES]
                evs[k] = verify.call_events(r, r.recs[i])
            mark = (len(tape), len(irqs))
            st.sounds = SoundLog(st)
            try:
                rm.frame(st, FrameInput(at_call=at, events_at_call=evs))
            except (rm.StopRun, Exception) as e:          # the cut last frame: dropped
                del tape[mark[0]:]
                del irqs[mark[1]:]
                if not isinstance(e, rm.StopRun) and 'no more calls' not in str(e):
                    raise
                break
            truth = sum(1 for i in orc.recs if r.recs[i]['kind'] == 'irq_pre')
            if st.frame_vbls != truth:
                raise SystemExit('%s frame %d: the model took %d VBLs, the harness %d'
                                 % (name, f, st.frame_vbls, truth))
            frames.append([state_crc(st, REGIONS), st.frame_vbls, list(st.sounds)])
            n_ok += 1
    finally:
        rm.run_call = orig_run_call
        d_player.tick = orig_tick
    print('%s: %d frames, %d tape ints, %d irqs, %d moved VBLs' % (
        name, n_ok, len(tape), sum(1 for _ in _irq_iter(irqs)), drv.moved_irqs), file=sys.stderr)
    return dict(init=init, tape=tape, irqs=irqs, frames=frames, per_call=per_call)


def _irq_iter(irqs):
    i = 0
    while i < len(irqs):
        yield i
        i += 1 + 2 * irqs[i]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dumps', nargs='+')
    ap.add_argument('--calls', action='store_true')
    ap.add_argument('--out', default=os.path.join(ROOT, 'apps', 'rick_dangerous_fixture.json.gz'))
    a = ap.parse_args()
    runs = {}
    for d in a.dumps:
        runs[d] = run(d, a.calls)
    out = dict(regions=[list(x) for x in REGIONS], runs=runs)
    with gzip.open(a.out, 'wt') as f:
        json.dump(out, f, separators=(',', ':'))
    print('%s: %d bytes' % (a.out, os.path.getsize(a.out)), file=sys.stderr)


if __name__ == '__main__':
    main()
