"""compare.py <pixdir> <vicedir> [frame ...]: the scene's frames (replay.zig's f<N>.pix/.border)
against VICE captures (capture.py's f<N>.png), in C64 colour indices over VICE's 384x272 view
(raster lines 16..287, X -8..375: physical row y+5, column x+8 of the machine's 400x280).
Without frames, every f<N>.pix in <pixdir> that has a capture. Prints mismatching frames."""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import vicmodel  # noqa: E402

W, H, COLS = 384, 272, 400


def ours(pixdir: str, n: int) -> list[list[int]]:
    pix = open(os.path.join(pixdir, f"f{n}.pix"), "rb").read()
    b = open(os.path.join(pixdir, f"f{n}.border"), "rb").read()  # border, split_x lo/hi, split_c
    border, sc = b[0:280], b[840:1120]
    sx = [b[280 + 2 * r] | b[281 + 2 * r] << 8 for r in range(280)]
    out = []
    for y in range(H):
        r = y + 5
        row = pix[r * COLS + 8:r * COLS + 8 + W]
        out.append([p - 1 if p else (sc[r] if sx[r] and x + 8 >= sx[r] else border[r]) for x, p in enumerate(row)])
    return out


def main() -> None:
    pixdir, vicedir = sys.argv[1], sys.argv[2]
    frames: list[int] = [int(a) for a in sys.argv[3:]] or sorted(
        int(os.path.basename(p)[1:-4]) for p in glob.glob(os.path.join(pixdir, "f*.pix")))
    bad = 0
    for n in frames:
        png = os.path.join(vicedir, f"f{n}.png")
        if not os.path.exists(png) or not os.path.exists(os.path.join(pixdir, f"f{n}.pix")):
            frames = [f for f in frames if f != n]
            continue
        cnt, box = vicmodel.diff(ours(pixdir, n), vicmodel.png_indices(png))
        if cnt:
            bad += 1
            print(f"f{n} mismatch {cnt} {box}")
    print(f"{len(frames) - bad}/{len(frames)} frames exact")


if __name__ == "__main__":
    main()
