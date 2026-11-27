"""The Track Kit's error table, the rest (R82 M7): the Car Kit, the panorama writer, the track pack builder, and the reasons
the CART gives for a file it refuses (its console line `racer,track,refused,<NAME>,<why>`, `racer,car,refused,...`,
`racer,pan,refused,...`, and the select screen). The track side is kit_errors.py; the same test checks both.
"""

from __future__ import annotations

from typing import Final

MORE: Final[dict[str, dict[str, str]]] = {
    "kcar_export": {  # the Car Kit export
        "object {}: no car part {} (one of {})": "name each car mesh car_wheels, car_hull, car_cabin, car_wing, car_shadow or car_lod1",
        "{} face {}: the engine's normal disagrees with Blender's (winding)": "a bent or concave car face: flatten it or split it",
        "not a {} v{} document": "the file is not a Car Kit export: re-export it with the add-on",
    },
    "carcheck": {  # the car's budget and shape checks (the Car Kit meter)
        "HARD limit: {}: material {} is not a car material ({})": "use body, stripe, dark, glass, rim, head, tail or shadow",
        "HARD limit: {}: a fixed colour needs a ramp 12..18 and a level 0..7": "a `fixed` face names its ramp (12..18) and level (0..7)",
        "HARD limit: {} has {} vertices (a face record holds 3 or 4)": "triangulate n-gons on the car",
        "HARD limit: {}: a vertex id is past the {} vertices": "a hand-edited document: re-export it",
        "HARD limit: {} has no area (no normal)": "merge the degenerate face's vertices away",
        "HARD limit: the shadow part must be exactly one quad of material shadow (the cart darkens one quad a car)":
            "car_shadow is one quad on the ground, material shadow",
        "HARD limit: the shadow quad must lie flat on the ground (y {}..{} Q7)": "put the shadow quad at the car's ground level",
        "HARD limit: part {} is missing (the cart draws {})": "every car needs car_hull and car_lod1 (and its shadow)",
        "{} limit: {} {} > {}": "a car meter row over its limit: fewer faces or vertices (the far model: 12 faces)",
        "HARD limit: {} is not planar (the 4th vertex is off the others' plane)": "flatten the quad or split it",
        "HARD limit: {} is not convex (the fill draws convex polygons)": "split the concave face",
        "HARD limit: material shadow is only for the shadow part ({})": "give the face another car material",
        "SOFT limit: the car is {}..{} on {}, the envelope is {}..{} (Q7)":
            "the car is bigger than the cart's car envelope: scale it down (or let carc.py --scale size it)",
        "HARD limit: no car part {}": "add the missing car_<part> object",
    },
    "carc": {  # the car file writer
        "the footprint takes the car past {} vertices": "the shadow footprint adds vertices: fewer vertices on the hull",
        "a set holds 1..{} models and {} ramp colours": "a car set file holds 1..5 cars and a palette of 7 colours",
    },
    "panc": {  # the panorama writer (<TRACK>.PAN)
        "no {} free entries on the track's {} ramps": "the track's ramps have too few unused entries: fewer track materials, or fewer strip colours",
        "{} rows do not fit {} upper + {} lower rows": "the strip is too tall: at most 128 rows above the horizon split, 160 below",
        "a {} x {} strip ({} texels, u0 {}): width a power of two 256..1024": "the strip's width is 256, 512 or 1024 texels a full turn",
        "entries {}..{}: off the fixed entries, the car ramps and 255": "choose entries on the track's own ramps (panc picks them for you)",
    },
    "trackpack": {  # the track pack builder
        "{} tracks: the cart lists {} besides its oval": "split the pack: at most 15 tracks (disk and C: together)",
        "no .KTR in the pack": "a disk pack needs a track",
        "{}: no {}.KTR here: it is used only when a track of that name is on show": "a warning: a car file named for no track here",
        "no {}: build the cart first (./build.sh --fast)": "the disk pack carries the racer cart: build it, or give --cart",
        "{}: not an 8.3 name of A-Z 0-9 _ ending .KTR, .KCR or .PAN": "rename the file: up to 8 letters, digits or _, then .KTR / .KCR / .PAN",
        "{}: twice in the pack": "two files with one name (case does not count): keep one",
        "{} files: a disk's FAT holds 23 besides the cart": "split the pack over two disks",
        "{}: refused ({})": "the file is ZX0-packed but its stream is broken: pack it again (zx0pack) or give the raw file",
        "{}: the cart reads a panorama from its own disk only: put it in a --zmd pack": "panoramas go on a disk pack, not C:",
        "{}: no {}.KTR in the pack (a panorama is checked against its track's palette)": "add the panorama's track to the pack",
        "{}: the cart refuses it ({})": "the cart's reason, below (the same name the cart logs)",
    },
}

CART: Final[dict[str, str]] = {  # the cart's reasons (the console, the select screen's refusals)
    "Truncated": "the file is shorter than its header says (a copy cut short): copy it again",
    "BadMagic": "not a Kestrel Racing file of that kind (.KTR a track, .KCR a car, .PAN a panorama)",
    "BadVersion": "written by another version of the converter: convert it again with this Track Kit",
    "BadCrc": "the bytes changed after the converter wrote them (a bad copy, a hand edit): convert or copy it again",
    "BadBlock": "a count or offset in the header points outside the file: convert it again",
    "BadMood": "the mood block is out of range (the draw distance cap 0 or 3..8, the clock, the haze): fix the mood and convert",
    "BadPack": "a ZX0-packed file whose stream is broken: pack it again",
    "ReadFailed": "the disk or the card could not read the file: check the card",
    "TooBig": "over the cart's buffers (a track over 25,600 vertices or 10,240 faces, a car file over 32 KB)",
    "BadFace": "a car face with more than 4 vertices, a vertex past the model, or a decal: convert the car again",
    "BadParts": "a car's parts are out of order or missing (a hull, a far model, 1..16 shadow faces): convert the car again",
    "BadSize": "a panorama's width (256..1024, a power of two), rows or horizon are out of range",
    "BadColours": "a panorama's colours are off the palette or over the car ramps (12..18)",
    "BadTexel": "a panorama texel uses a colour the strip does not own",
    "Clash": "the panorama's entries are not on its track's ramps, or a face of the track uses them: make it with panc for THIS track",
    "not_track": "the scan: the file's first bytes are no track (magic, version, size): the select shows INVALID",
    "too_big": "the scan: over the 1 MiB track buffer once depacked: TOO BIG",
    "no_ram": "the scan: the cart's RAM cannot hold the largest track listed: NO RAM (the largest file is dropped)",
    "bad_car": "a car file was refused (the reason is in the console): the built-in GT is drawn, BAD CAR",
    "bad_pan": "a panorama was refused (the reason is in the console): the mood's backdrop shape is drawn, BAD PAN",
}
