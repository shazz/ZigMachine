"""frames.py: read trace_all.py's stream back as frames.

Frame n's stores = those after line 288 of frame n-1 (lines 288..311 and 0..10, written after
the '#' of block n-1) plus block n's stores before its '#'. A store is (line, cycle, addr,
value-string). Lines 288..311 sort before 0 in a frame."""
import sys

Store = tuple[int, int, int, str]


def load(path: str) -> dict[int, list[Store]]:
    frames: dict[int, list[Store]] = {}
    carry: list[Store] = []
    cur: list[Store] | None = None
    n = 0
    for ln in open(path):
        if ln.startswith("F "):
            n = int(ln.split()[1])
            cur = list(carry)
            carry = []
            frames[n] = cur
        elif ln.startswith("#"):
            cur = carry
        else:
            line, cyc, addr, val = ln.split()
            cur.append((int(line), int(cyc), int(addr, 16), val))
    return frames


def events(frames: dict[int, list[Store]], addr: int) -> list[tuple[int, Store]]:
    return [(n, s) for n, st in sorted(frames.items()) for s in st if s[2] == addr]


if __name__ == "__main__":
    fr = load(sys.argv[1])
    for n, s in events(fr, 0xDD00) + events(fr, 0x1FFE):
        print(n, s)
