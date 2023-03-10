from PIL import Image
import argparse
from collections.abc import Iterator
import itertools
import struct
from pathlib import Path

# python tools/convert_font.py assets/blade_font.png assets/blade_font.pal 40 34 ABCDEFGHIJKLMNOPQRSTUVWXYZ
# python tools/convert_font.py assets/ancool_font.png assets/ancool_font2.pal 32 16 " !       '   -. 0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ"

DEFAULT_ALPHA = 255


def grouper(iterator: Iterator, n: int) -> Iterator[list]:
    while chunk := list(itertools.islice(iterator, n)):
        yield chunk


parser = argparse.ArgumentParser(prog="PNG Font to raw converter", description="Convert a PNG file to a palette based raw image", epilog="(C) 2023 TRSi")

parser.add_argument("png_file")
parser.add_argument("palette_file")
parser.add_argument("char_width")
parser.add_argument("char_height")
parser.add_argument("characters")
args = parser.parse_args()

char_width = int(args.char_width)
char_height = int(args.char_height)

characters = args.characters

output_filename = f'{args.png_file.rsplit(".")[0]}_interlaced.raw'

print(f"Parsing font {args.png_file} with {len(characters)} characters of size: ({char_width},{char_height})")

with Image.open(args.png_file) as im:
    print(f"Image loaded: {im.format} {im.format_description} {im.size} {im.mode}")

    linear_palette = []

    if im.mode in ["P", "PA"]:
        nb_colors = 3 if im.mode == "P" else 4

        assert len(characters) * char_width == im.width, f"{len(characters)} * {char_width} = {len(characters) * char_width} vs {im.width}"
        assert char_height == im.height

        palette = im.getpalette()

        print(f"Extracting RGB(A) palette ({len(palette)//nb_colors})")
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
            print(f"Adding {missing_colors} null colors ({len(filler)} entries) to the palette of {len(linear_palette)} entries")

            linear_palette += filler

        # print(linear_palette)

        assert len(linear_palette) == 256 * 4, f"palette size {len(linear_palette)} should be {256*4}"
        pal_bytes = struct.pack("{}B".format(len(linear_palette)), *linear_palette)

        with open(args.palette_file, "wb") as fp:
            fp.write(pal_bytes)

        data = list(im.getdata())
        reordered_list = []
        for idx, char in enumerate(characters):
            print(f"Extracting character {idx}: {char}")
            for row in range(char_height):
                print(f"\trow: {row} of {range(char_height)}")

                row_width = row * im.width
                start_offset = (idx * char_width) + (row_width)
                end_offset = ((idx + 1) * char_width) + (row_width)

                print(f"\t\t{row_width=} {start_offset=} {end_offset=}")

                print(f"\t\tslice : [{data[start_offset:end_offset]}]")
                reordered_list += data[start_offset:end_offset]

        img_bytes = struct.pack("{}B".format(len(reordered_list)), *reordered_list)
        with open(output_filename, "wb") as fi:
            fi.write(img_bytes)

    else:
        raise RuntimeError(f"Unsupported image mode: {im.mode}")
