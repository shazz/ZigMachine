"""pin_frames.py <vicedir> <frame>...: SHA-256 of VICE captures as C64 colour indices.

The image is VICE's 384x272 view (raster lines 16..287), one byte per pixel = the colodore
palette index (capture.py runs VICE with the neutral colour pipeline, so every pixel IS a
palette entry). apps/c64_1988_headless.mjs hashes the cart's composite the same way: these
are its pinned references. Prints a JS object literal."""
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import vicmodel  # noqa: E402

vicedir = sys.argv[1]
pins = []
for f in sys.argv[2:]:
    idx = vicmodel.png_indices(os.path.join(vicedir, f"f{f}.png"))
    flat = bytes(c for row in idx for c in row)
    assert -1 not in (c for row in idx for c in row), f"f{f}: a pixel off the palette"
    lit = sum(1 for c in flat if c != flat[0])
    pins.append(f'    {f}: "{hashlib.sha256(flat).hexdigest()}", // {lit} px not the corner colour')
print("{\n" + "\n".join(pins) + "\n}")
