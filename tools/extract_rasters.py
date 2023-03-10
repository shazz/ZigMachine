from PIL import Image
import argparse
from collections.abc import Iterator
import itertools
import struct
from pathlib import Path

# python tools/extract_rasters.py src/assets/logo_283x124.png src/assets/sprite.pal
# python tools/extract_rasters.py src/assets/screens/df/rasters.png src/assets/screens/df/rasters_pal.dat 
# python tools/extract_rasters.py src/assets/screens/df/colorCycle.png src/assets/screens/df/top_raster_pal.dat 
# python tools/extract_rasters.py src/assets/screens/ics/rast.png src/assets/screens/ics/raster_pal.dat 
# python tools/extract_rasters.py src/assets/screens/bladerunners/raster_back.png src/assets/screens/bladerunners/raster_back_pal.dat 
# python tools/extract_rasters.py src/assets/screens/bladerunners/raster_font.png src/assets/screens/bladerunners/raster_font_pal.dat 

# python tools/extract_rasters.py src/assets/screens/reps4/rasterGray.png src/assets/screens/reps4/rasterGray_pal.dat 
# python tools/extract_rasters.py src/assets/screens/reps4/rasterPink.png src/assets/screens/reps4/rasterPink_pal.dat 
# python tools/extract_rasters.py src/assets/screens/reps4/rasterBlue.png src/assets/screens/reps4/rasterBlue_pal.dat 
# python tools/extract_rasters.py src/assets/screens/reps4/rasterYellow.png src/assets/screens/reps4/rasterYellow_pal.dat 
# python tools/extract_rasters.py src/assets/screens/reps4/rasterFonts.png src/assets/screens/reps4/rasterFonts_pal.dat 

# python tools/extract_rasters.py src/assets/screens/stcs/rasters.png src/assets/screens/stcs/rasters.dat 
# python tools/extract_rasters.py src/assets/screens/fallen_angels/rasters.png src/assets/screens/fallen_angels/rasters.dat 
# python tools/extract_rasters.py src/assets/screens/df2/rasters.png src/assets/screens/df2/rasters.dat 
# python tools/extract_rasters.py src/assets/screens/df2/scrollrasters.png src/assets/screens/df2/scrollrasters.dat 
# python tools/extract_rasters.py src/assets/screens/dbug/rasters.png src/assets/screens/dbug/rasters.dat 
# python tools/extract_rasters.py src/assets/screens/fullscreen/rasters.png src/assets/screens/fullscreen/rasters.dat 

DEFAULT_ALPHA = 255


def grouper(iterator: Iterator, n: int) -> Iterator[list]:
    while chunk := list(itertools.islice(iterator, n)):
        yield chunk


parser = argparse.ArgumentParser(prog="PNG Rasterbar extractor", description="Convert a PNG file to a palette based raw image", epilog="(C) 2023 TRSi")

parser.add_argument("png_file")
parser.add_argument("colors_file")
args = parser.parse_args()

output_filename = f'{args.png_file.rsplit(".")[0]}.raw'

with Image.open(args.png_file) as im:
    print(f"Image loaded: {im.format} {im.format_description} {im.size} {im.mode}")

    rasters_colors = []

    if im.width != 1:
        raise RuntimeError(f"Rasters bar should be 1 pixel wide")

    if im.mode in ["RGB", "RGBA"]:

        pixels = im.getdata()
        for pixel in pixels:
            rasters_colors.append(pixel[0])
            rasters_colors.append(pixel[1])
            rasters_colors.append(pixel[2])
            rasters_colors.append(pixel[3] if im.mode == "RGBA" else 255)

        print(f"colors: {len(rasters_colors)}")
        if len(rasters_colors) < 256*4:
            rasters_colors += [0 for i in range(0, 256 * 4 - len(rasters_colors))]


        assert len(rasters_colors) == 256 * 4, f"colors: {len(rasters_colors)}"

        color_bytes = struct.pack("{}B".format(len(rasters_colors)), *rasters_colors)

        with open(args.colors_file, "wb") as fp:
            fp.write(color_bytes)
    else:
        raise RuntimeError(f"Unsupported image mode: {im.mode}")
