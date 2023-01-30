from PIL import Image, ImageOps
import argparse
from collections.abc import Iterator
import itertools
import struct
from pathlib import Path

DEFAULT_ALPHA = 255

# python tools/convert_bitmap_font.py src/assets/screens/ancool/fonts.png 32 17 10 60

# python tools/convert_bitmap_font.py src/assets/screens/empire/fonts2.png 32 32 10 60
# python tools/convert_bitmap_font.py src/assets/screens/df/fonts2.png 32 30 10 60
# python tools/convert_bitmap_font.py src/assets/screens/ics/font_noics.png 16 16 44 94
# python tools/convert_bitmap_font.py src/assets/screens/bladerunners/fonts.png 32 32 10 80

# python tools/convert_bitmap_font.py -i src/assets/screens/leonard/font.png -r src/assets/screens/leonard/font.raw -cw 6 -ch 6 -cpr 10 -nb 60 -tmp
# python tools/convert_bitmap_font.py -i src/assets/screens/reps4/fonts.png -r src/assets/screens/reps4/fonts.raw -cw 16 -ch 16 -cpr 10 -nb 60 -m -tmp
# python tools/convert_bitmap_font.py -i src/assets/screens/the_union/fonts.png -r src/assets/screens/the_union/fonts.raw -cw 32 -ch 17 -cpr 10 -nb 60 -m -tmp
# python tools/convert_bitmap_font.py -i src/assets/screens/stcs/font40x34_c1.png -r src/assets/screens/stcs/font40x34_c1.raw -p src/assets/screens/stcs/font40x34_c1_pal.dat -cw 40 -ch 34 -cpr 8 -nb 64 -tmp
# python tools/convert_bitmap_font.py -i src/assets/screens/stcs/font40x34_c2.png -p src/assets/screens/stcs/font40x34_c2_pal.dat -cw 40 -ch 34 -cpr 8 -nb 64
# python tools/convert_bitmap_font.py -i src/assets/screens/stcs/font40x34_c3.png -p src/assets/screens/stcs/font40x34_c3_pal.dat -cw 40 -ch 34 -cpr 8 -nb 64

# python tools/convert_bitmap_font.py -i src/assets/screens/equinox/fonts.png -r src/assets/screens/equinox/fonts.raw -p src/assets/screens/equinox/fonts_pal.dat -cw 32 -ch 26 -cpr 10 -nb 60

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

parser = argparse.ArgumentParser(prog="PNG Font to raw converter", description="Convert a PNG file to a palette based font image", epilog="(C) 2023 TRSi")


parser.add_argument("-i",   "--png_file", metavar = "IMAGE", help="Path to your input PNG file in palette mode", required=True)
parser.add_argument("-p",   "--palette_file", metavar="PALETTE", help="Path to the output palette file", required=False)
parser.add_argument("-r",   "--raw_file", metavar="RAW", help="Path to the output raw image file", required=False)
parser.add_argument("-cw",   "--char_width", metavar="WIDTH", help="Character width", required=True)
parser.add_argument("-ch",   "--char_height", metavar="HEIGHT", help="Character height", required=True)
parser.add_argument("-cpr", "--chars_per_row", metavar="ROW", help="Characters per row", required=True)
parser.add_argument("-nb",  "--nb_chars", metavar="TOTAL", help="Characters total number", required=True)
parser.add_argument("-m",   "--mask", help="generate mask", action='store_true')
parser.add_argument("-tmp", "--tmp_png", help="save temporary png", action='store_true')
args = parser.parse_args()


char_width = int(args.char_width)
char_height = int(args.char_height)
nb_chars = int(args.nb_chars)
chars_per_row = int(args.chars_per_row)
gen_mask = bool(args.mask)


print(f"Parsing font {args.png_file} with {nb_chars} characters of size: ({char_width},{char_height})")

with Image.open(args.png_file) as im:
    print(f"Image loaded: {im.format} {im.format_description} {im.size} {im.mode} {len(im.getcolors())}")

    linear_palette = []

    if im.mode in ["P"]:

        data = list(im.getdata())
        reordered_data = []

        print(data, len(data))

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
        if args.tmp_png:
            im2.save(args.raw_file + ".png", "PNG")

        if gen_mask:
            if len(im.getcolors()) > 2:
                raise Exception(f"Cannot generate mask for more than 1 color: {im.getcolors()}")
            data = [0 if entry == 0 else 255 for entry in data]

        print(data[0: char_width*char_height], len(data))
        print(data[char_width*char_height: char_width*char_height*2], len(data))

        if args.raw_file:
            img_bytes = struct.pack("{}B".format(len(data)), *data)
            with open(args.raw_file, "wb") as fi:
                fi.write(img_bytes)

        if args.palette_file:
            extract_palette(im2, im2.mode, args.palette_file)

    else:
        raise RuntimeError(f"Unsupported image mode: {im.mode}")
