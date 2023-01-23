from PIL import Image, ImageOps
import argparse
from collections.abc import Iterator
import itertools
import struct
from pathlib import Path

DEFAULT_ALPHA = 255

# python tools/convert_bitmap_font.py src/assets/screens/ancool/fonts.png 32 17 10 60
# python tools/convert_bitmap_font.py src/assets/screens/leonard/font.png 6 6 10 60
# python tools/convert_bitmap_font.py src/assets/screens/empire/fonts2.png 32 32 10 60
# python tools/convert_bitmap_font.py src/assets/screens/df/fonts2.png 32 30 10 60
# python tools/convert_bitmap_font.py src/assets/screens/ics/font_noics.png 16 16 44 94
# python tools/convert_bitmap_font.py src/assets/screens/bladerunners/fonts.png 32 32 10 80
# python tools/convert_bitmap_font.py src/assets/screens/reps4/fonts.png 16 16 10 60


def grouper(iterator: Iterator, n: int) -> Iterator[list]:
    while chunk := list(itertools.islice(iterator, n)):
        yield chunk

def extract_palette(image, mode, filename):

    linear_palette = []
    nb_colors = 3 if mode == "P" else 4   

    palette = image.getpalette()

    print(f"Extracting RGB(A) palette ({len(palette)//nb_colors})")
    print(palette)
    if len(palette) // nb_colors > 256:
        raise RuntimeError(f"Current palette has more than 256 colors: {len(palette)//nb_colors}")

    missing_colors = 256 - len(palette) // nb_colors

    if image.mode == "P":
        rgb_chunks = list(grouper(iter(palette), 3))
        for index, chunk in enumerate(rgb_chunks):
            linear_palette.append(chunk[0])
            linear_palette.append(chunk[1])
            linear_palette.append(chunk[2])
            linear_palette.append(DEFAULT_ALPHA if index != 0 else 0)
    else:
        linear_palette = palette

    if missing_colors > 0:
        filler = [0 for i in range(missing_colors * 4)]
        linear_palette += filler

    # print(linear_palette)

    assert len(linear_palette) == 256 * 4
    pal_bytes = struct.pack("{}B".format(len(linear_palette)), *linear_palette)

    with open(filename, "wb") as fp:
        fp.write(pal_bytes)

parser = argparse.ArgumentParser(prog="PNG Font to raw converter", description="Convert a PNG file to a palette based raw image", epilog="(C) 2023 TRSi")

parser.add_argument("png_file")
parser.add_argument("char_width")
parser.add_argument("char_height")
parser.add_argument("chars_per_row")
parser.add_argument("nb_chars")
args = parser.parse_args()

char_width = int(args.char_width)
char_height = int(args.char_height)
nb_chars = int(args.nb_chars)
chars_per_row = int(args.chars_per_row)

output_filename = f'{args.png_file.rsplit(".")[0]}_pal'

print(f"Parsing font {args.png_file} with {nb_chars} characters of size: ({char_width},{char_height})")

with Image.open(args.png_file) as im:
    print(f"Image loaded: {im.format} {im.format_description} {im.size} {im.mode} {len(im.getcolors())}")

    linear_palette = []

    if im.mode in ["P"]:

        data = list(im.getdata())
        reordered_data = []

        # print(data, len(data))

        for char in range(0, nb_chars):
            for y in range(0, char_height):
                row_offset = (char // chars_per_row) * (chars_per_row * char_width * char_height)
                line_offset = y * chars_per_row * char_width 
                char_start_offset = (char % chars_per_row) * char_width
                char_end_offset = ((char % chars_per_row) + 1) * char_width
                
                row = data[row_offset + line_offset + char_start_offset : row_offset + line_offset + char_end_offset]

                print(f"{char=}, {row_offset=}, {line_offset=}, {char_start_offset=} {char_end_offset=} len={len(row)}")

                reordered_data += row
            
        # print(reordered_data)
        im2 = Image.new("P", (char_width, nb_chars * char_height))
        im2.putpalette(im.getpalette())
        im2.putdata(reordered_data)

        data = list(im2.getdata())
        im2.save(output_filename + ".png", "PNG")

        print(data[0: char_width*char_height], len(data))
        print(data[char_width*char_height: char_width*char_height*2], len(data))

        img_bytes = struct.pack("{}B".format(len(data)), *data)
        with open(output_filename + ".raw", "wb") as fi:
            fi.write(img_bytes)

        extract_palette(im2, im2.mode, output_filename + ".dat")

    else:
        raise RuntimeError(f"Unsupported image mode: {im.mode}")
