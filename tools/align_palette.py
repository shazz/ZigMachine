from PIL import Image
import argparse
from collections.abc import Iterator
import itertools
import struct
from pathlib import Path

DEFAULT_ALPHA = 255

# python tools/align_palette.py src/assets/screens/the_union/DELTA.png src/assets/screens/the_union/logo_pal.dat src/assets/screens/the_union/DELTA.raw


def grouper(iterator: Iterator, n: int) -> Iterator[list]:
    while chunk := list(itertools.islice(iterator, n)):
        yield chunk


parser = argparse.ArgumentParser(prog="PNG Palette aligner", description="Convert a PNG file to a palette based raw image", epilog="(C) 2023 TRSi")

parser.add_argument("png_file")
parser.add_argument("palette_file")
parser.add_argument("raw_file")
args = parser.parse_args()

output_filename = f'{args.png_file.rsplit(".")[0]}.raw'

with open(args.palette_file, "rb") as pal_file:
    target_palette = pal_file.read()

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
            rgb_chunks = list(grouper(iter(palette), 4))
            linear_palette = palette

        mapping = {}
        source_rgb_chunks = list(grouper(iter(list(linear_palette)), 4))
        aligned_rgb_chunks = list(grouper(iter(list(target_palette)), 4))

        for idx, chunk in enumerate(source_rgb_chunks):
            for aligned_idx, aligned_chunk in enumerate(aligned_rgb_chunks):

                if chunk == aligned_chunk:
                    mapping[idx] = aligned_idx
                    break

            if idx not in mapping:
                raise Exception(f"Color {chunk} not found in aligned palette")

        print(mapping)

        with open(args.raw_file, "rb") as raw_file:
            raw_data = raw_file.read()

        pal_entries = list(raw_data)
        for idx in range(len(pal_entries)):
            entry = pal_entries[idx]
            pal_entries[idx] = mapping[entry]

        entries_bytes = struct.pack("{}B".format(len(pal_entries)), *pal_entries)
        with open(args.raw_file + ".new", "wb") as modified_raw_file:
            modified_raw_file.write(entries_bytes)

    else:
        raise RuntimeError(f"Unsupported image mode: {im.mode}")
