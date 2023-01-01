from PIL import Image
import argparse
from collections.abc import Iterator
import itertools
import struct
from pathlib import Path

DEFAULT_ALPHA = 255

def grouper(iterator: Iterator, n: int) -> Iterator[list]:
    while chunk := list(itertools.islice(iterator, n)):
        yield chunk

parser = argparse.ArgumentParser(
                    prog = 'PNG to raw converter',
                    description = 'Convert a PNG file to a palette based raw image',
                    epilog = '(C) 2023 TRSi')

parser.add_argument('png_file')   
parser.add_argument('palette_file')
args = parser.parse_args()

output_filename = f'{args.png_file.rsplit(".")[0]}.raw'

with Image.open(args.png_file) as im:
    print(f"Image loaded: {im.format} {im.format_description} {im.size} {im.mode}")

    linear_palette = []

    if im.mode in ["P", "PA"]:
        print("Extracting RGB(A) palette")
        palette = im.getpalette()

        if len(im.getcolors()) > 256:
            raise RuntimeError(f"Current palette has more than 256 colors: {len(im.getcolors())}")

        missing_colors = 256 - len(im.getcolors())

        if im.mode == 'P':
            rgb_chunks = list(grouper(iter(palette), 3))
            for chunk in rgb_chunks:
                linear_palette.append(chunk[0])
                linear_palette.append(chunk[1])
                linear_palette.append(chunk[2])
                linear_palette.append(DEFAULT_ALPHA)
        else:
            linear_palette = palette

        if missing_colors > 0:
            filler = [0 for i in range(missing_colors*4)]
            linear_palette += filler

        print(linear_palette)

        assert len(linear_palette) == 256*4
        pal_bytes = struct.pack("{}B".format(len(linear_palette)), *linear_palette)

        with open(args.palette_file, "wb") as fp:
            fp.write(pal_bytes)

        data = list(im.getdata())
        if len(data) != im.width*im.height:
            raise RuntimeError(f"Data sie is expected to be {im.width*im.height} and not {len(data)}")
        
        img_bytes = struct.pack("{}B".format(len(data)), *data)
        with open(output_filename, "wb") as fi:
            fi.write(img_bytes)

    else:
        raise RuntimeError(f"Unsupported image mode: {im.mode}")

    
