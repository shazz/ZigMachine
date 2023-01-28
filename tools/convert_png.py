from PIL import Image
import argparse
from collections.abc import Iterator
import itertools
import struct
from pathlib import Path

DEFAULT_ALPHA = 255

# python tools/convert_png.py -i assets/logo_283x124.png assets/sprite.pal
# python tools/convert_png.py -i src/assets/screens/leonard/back.png src/assets/screens/leonard/back_pal.dat 
# python tools/convert_png.py -i src/assets/screens/leonard/ball.png src/assets/screens/leonard/ball_pal.dat 
# python tools/convert_png.py -i src/assets/screens/df/top_logo.png src/assets/screens/df/top_logo_pal.dat 
# python tools/convert_png.py -i src/assets/screens/ics/grid.png src/assets/screens/ics/grid_pal.dat 
# python tools/convert_png.py -i src/assets/screens/ics/grid_unit.png src/assets/screens/ics/grid_unit_pal.dat
# python tools/convert_png.py -i src/assets/screens/ics/ics_logo.png src/assets/screens/ics/ics_logo_pal.dat 
# python tools/convert_png.py -i src/assets/screens/reps4/back_bottom.png src/assets/screens/reps4/back_bottom_pal.dat 
# python tools/convert_png.py -i src/assets/screens/reps4/back_top.png src/assets/screens/reps4/back_top_pal.dat 
# python tools/convert_png.py -i src/assets/screens/reps4/logo.png src/assets/screens/reps4/logo_pal.dat 
# python tools/convert_png.py -i src/assets/screens/reps4/back_mask.png src/assets/screens/reps4/back_mask_pal.dat 
# python tools/convert_png.py -i src/assets/screens/reps4/fonts_mask.png src/assets/screens/reps4/fonts_mask_pal.dat 
# python tools/convert_png.py -i src/assets/screens/fullscreen/modmate.png src/assets/screens/fullscreen/modmate_pal.dat
# python tools/convert_png.py -i src/assets/screens/fullscreen/center.png src/assets/screens/fullscreen/center_pal.dat
# python tools/convert_png.py -i src/assets/screens/fullscreen/top.png src/assets/screens/fullscreen/top_pal.dat
# python tools/convert_png.py -i src/assets/screens/fullscreen/bottom.png src/assets/screens/fullscreen/bottom_pal.dat
# python tools/convert_png.py -i src/assets/screens/fullscreen/left.png src/assets/screens/fullscreen/left_pal.dat
# python tools/convert_png.py -i src/assets/screens/fullscreen/right.png src/assets/screens/fullscreen/right_pal.dat

# python tools/convert_png.py -i src/assets/screens/the_union/back.png -r src/assets/screens/the_union/back.raw  -p src/assets/screens/the_union/back_pal.dat 
# python tools/convert_png.py -i src/assets/screens/the_union/backblue.png -p src/assets/screens/the_union/blue_back_pal.dat 

# python tools/convert_png.py -i src/assets/screens/the_union/logo.png -p src/assets/screens/the_union/logo_pal.dat 
# python tools/convert_png.py -i src/assets/screens/the_union/DELTA.png -r src/assets/screens/the_union/delta.raw 
# python tools/convert_png.py -i src/assets/screens/the_union/H.png -r src/assets/screens/the_union/h.raw 
# python tools/convert_png.py -i src/assets/screens/the_union/O.png -r src/assets/screens/the_union/o.raw 
# python tools/convert_png.py -i src/assets/screens/the_union/W.png -r src/assets/screens/the_union/w.raw 
# python tools/convert_png.py -i src/assets/screens/the_union/D.png -r src/assets/screens/the_union/d.raw 
# python tools/convert_png.py -i src/assets/screens/the_union/Y.png -r src/assets/screens/the_union/y.raw 

# python tools/convert_png.py -i src/assets/screens/stcs/logoY.png -r src/assets/screens/stcs/logo.raw -p src/assets/screens/stcs/logo_pal.dat

def grouper(iterator: Iterator, n: int) -> Iterator[list]:
    while chunk := list(itertools.islice(iterator, n)):
        yield chunk


parser = argparse.ArgumentParser(prog="PNG to raw converter", description="Convert a PNG file to a palette based raw image", epilog="(C) 2023 TRSi")

parser.add_argument("-i", "--png_file", metavar = "IMAGE", help="Path to your input PNG file in palette mode", required=True)
parser.add_argument("-p", "--palette_file", metavar="PALETTE", help="Path to the output palette file", required=False)
parser.add_argument("-r", "--raw_file", metavar="RAW", help="Path to the output raw image file", required=False)
args = parser.parse_args()


with Image.open(args.png_file) as im:
    print(f"Image loaded: {im.format} {im.format_description} {im.size} {im.mode}")

    linear_palette = []

    if im.mode in ["P", "PA"]:
        nb_colors = 3 if im.mode == "P" else 4

        palette = im.getpalette()

        print(f"Extracting RGB(A) palette ({len(palette)//nb_colors})")
        # print(palette)
        if len(palette) // nb_colors > 256:
            raise RuntimeError(f"Current palette has more than 256 colors: {len(palette)//nb_colors}")

        missing_colors = 256 - len(palette) // nb_colors

        if im.mode == "P":
            rgb_chunks = list(grouper(iter(palette), 3))
            for chunk in rgb_chunks:
                linear_palette.append(chunk[0])
                linear_palette.append(chunk[1])
                linear_palette.append(chunk[2])
                linear_palette.append(DEFAULT_ALPHA)
        else:
            linear_palette = palette

        if missing_colors > 0:
            filler = [0 for i in range(missing_colors * 4)]
            linear_palette += filler

        # print(linear_palette)

        assert len(linear_palette) == 256 * 4
        pal_bytes = struct.pack("{}B".format(len(linear_palette)), *linear_palette)

        data = list(im.getdata())
        if len(data) != im.width * im.height:
            raise RuntimeError(f"Data sie is expected to be {im.width*im.height} and not {len(data)}")

        if args.palette_file:
            print(f"Saving palette file: {args.palette_file}")
            with open(args.palette_file, "wb") as fp:
                fp.write(pal_bytes)

        if args.raw_file:
            print(f"Saving pixel raw file: {args.raw_file}")
            img_bytes = struct.pack("{}B".format(len(data)), *data)
            with open(args.raw_file, "wb") as fi:
                fi.write(img_bytes)

    else:
        raise RuntimeError(f"Unsupported image mode: {im.mode}")
