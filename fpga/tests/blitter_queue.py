"""Randomised QUEUE scripts (memmap BLIT_CMD_QUEUE): the random ops of blitter_random.py, but
most of them packed into descriptor lists instead of run one by one.

While a list is being built, a register write goes into the WORKING COPY (the ops after it
see it, as the stale registers of blitter_random.py do) and marks its word for the next
descriptor; a `run` closes the descriptor (header: the mask of marked words, the COMMAND).
The list goes into the ring (one half, then the other, as the ZigOS queue does), Q_START and
Q_COUNT into the block, then `run 5`; the block is then the one before the list, as the
machine leaves it. Some lists are cut short, empty, or past the ring's end: refused or ended
early, the same on both sides. Plain ops run between the lists, so the block a list starts
from is whatever they left there."""

from blitter_random import RandomScript
from blitter_scripts import mm

HALF = mm.BLIT_QUEUE_WORDS // 2


class QueueScript(RandomScript):
    def __init__(self, seed: int) -> None:
        super().__init__(seed)
        self.desc: list[list[int]] | None = None  # the list being built, one word list per descriptor
        self.marked: set[int] = set()
        self.half = 0

    def w(self, size: int, off: int, v: int, p: float = 1.0) -> None:
        if self.desc is None:
            super().w(size, off, v, p)
        elif self.r.random() < p:
            for k in range(size // 8):
                self.reg[off + k] = (v >> (8 * k)) & 0xFF
            self.marked.add((off - mm.OFF_BLIT) // 4)

    def run(self) -> None:
        if self.desc is None:
            super().run()
            return
        if self.r.random() < 0.06:  # a destination below OFF_VRAM: a queued op there is refused
            self.w(32, mm.BLIT_D_BASE, self.r.randrange(0, mm.OFF_VRAM))
        mask = sum(1 << k for k in self.marked)
        cmd = self.cmd if self.r.random() < 0.9 else self.r.choice([0, 0, mm.BLIT_CMD_QUEUE, 9])
        words = [self.get(mm.OFF_BLIT + 4 * k, 32) for k in sorted(self.marked)]
        self.desc.append([mask | cmd << 24, *words])
        self.marked = set()

    def queue(self, ops: list, n: int) -> None:
        saved = dict(self.reg)
        self.desc = []
        for i in range(n):
            ops[self.r.randrange(len(ops))]()
            if self.r.random() < 0.1:  # a descriptor that only sets words
                self.w(8, mm.BLIT_COLOR, self.r.randrange(256))
                self.cmd = 0
                self.run()
        while sum(map(len, self.desc)) > HALF:  # a list fits its half of the ring
            self.desc.pop()
        words = [w for d in self.desc for w in d]
        self.desc = None
        self.reg = saved
        start = self.half * HALF + self.r.randrange(max(HALF - len(words), 1))
        self.half ^= 1
        guard = [mm.BLIT_CMD_FILL << 24] if start + len(words) < mm.BLIT_QUEUE_WORDS else []
        for i, w in enumerate(words + guard):  # the guard: a FILL that draws if the list is read past its end
            self.w(32, mm.OFF_BLIT_QUEUE + 4 * (start + i), w)
        count = len(words)
        kind = self.r.random()
        if kind < 0.08 and count:  # cut short in some descriptor
            count = self.r.randrange(count)
        elif kind < 0.1:  # past the ring's end: refused
            start, count = mm.BLIT_QUEUE_WORDS - self.r.randint(0, 3), max(count, 4)
        self.w(16, mm.BLIT_Q_START, start)
        self.w(16, mm.BLIT_Q_COUNT, count)
        self.cmd = mm.BLIT_CMD_QUEUE
        super().run()


def make_queue_script(seed: int, n: int) -> QueueScript:
    """n lists of 1 to 12 ops, a plain op between them now and then."""
    s = QueueScript(seed)
    ops = [s.blit, s.fill, s.poly_line, s.poly_tri]
    for i in range(n):
        if i % 25 == 24:
            s.lines.append(f"seed {seed + i}")
        s.queue(ops, s.r.randint(1, 12))
        if s.r.random() < 0.3:
            ops[i % 4]()
    return s
