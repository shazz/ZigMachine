"""Match the PATTERN area of each TFMX block (tune-specific) against the archive."""
import glob

from load import files
from tfmx import ARCH, blocks

arch = {p: open(p, 'rb').read() for p in glob.glob(f'{ARCH}/**/*.sndh', recursive=True)}
for k, d in files().items():
    for i, n, w in blocks(d):
        p0 = i + 0x20 + (w[0] + 1) * 64 + (w[1] + 1) * 64
        pat = d[p0:i + n]
        for o in range(0, len(pat) - 48, len(pat) // 6):
            pr = pat[o:o + 48]
            hits = [p for p, a in arch.items() if pr in a]
            print(k, hex(i), 'patlen', len(pat), 'probe@', o, [h[len(ARCH) + 1:] for h in hits][:6])
