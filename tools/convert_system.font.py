from PIL import Image, ImageOps
import argparse
from collections.abc import Iterator
import itertools
import struct
from pathlib import Path

DEFAULT_ALPHA = 255


def grouper(iterator: Iterator, n: int) -> Iterator[list]:
    while chunk := list(itertools.islice(iterator, n)):
        yield chunk


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

output_filename = f'{args.png_file.rsplit(".")[0]}_1bit'

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
                row = data[row_offset + line_offset + ((char % chars_per_row) * char_width) : row_offset + line_offset + (((char % chars_per_row) + 1) * char_width)]
                reordered_data += row

        # print(reordered_data)
        im2 = Image.new("P", (char_width, nb_chars * 8)).convert("1")
        im2.putdata(reordered_data)

        data = list(im2.getdata())

        im2 = im2.convert("L")
        im2 = ImageOps.invert(im2)
        im2.save(output_filename + ".png", "PNG")

        img_bytes = struct.pack("{}B".format(len(data)), *data)
        with open(output_filename + ".raw", "wb") as fi:
            fi.write(img_bytes)

    else:
        raise RuntimeError(f"Unsupported image mode: {im.mode}")
