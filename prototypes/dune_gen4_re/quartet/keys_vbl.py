"""keys_vbl.py FIFO AVI "VBL:SCANCODE ...": press keys into a running hatari --cmd-fifo at
emulated VBLs, not wall-clock seconds (../keys.sh): Hatari recording sound and PNG frames runs at
a fraction of real time, and not a steady one. The VBL is the number of frames the AVI holds so
far (recorded with --frameskips 0: one a VBL), counted as the file grows. Each key is held for
15 VBLs. Scancodes are decimal (57 Space, 59 F1 .. 64 F6).
"""
import os
import sys
import time

END = b'IEND\xaeB`\x82'


def main():
    fifo, avi, plan = sys.argv[1], sys.argv[2], sys.argv[3].split()
    events = []
    for ev in plan:
        at, code = (int(x) for x in ev.split(':'))
        events += [(at, f'keydown {code}'), (at + 15, f'keyup {code}')]
    events.sort()
    seen, pos, tail = 0, 0, b''
    while events:
        if not os.path.exists(avi) or not os.path.exists(fifo):
            time.sleep(0.2)
            continue
        with open(avi, 'rb') as f:
            f.seek(pos)
            chunk = f.read()
        pos += len(chunk)
        buf = tail + chunk
        seen += buf.count(END)
        tail = buf[-(len(END) - 1):]
        while events and seen >= events[0][0]:
            with open(fifo, 'w') as f:
                f.write(f'hatari-event {events[0][1]}\n')
            print(seen, events[0][1], flush=True)
            events.pop(0)
        time.sleep(0.05)


if __name__ == '__main__':
    main()
