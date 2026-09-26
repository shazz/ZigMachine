// The SWEDISH NEW YEAR assets as the harness reads them: the .raw images and
// the tables tools/private_tools/swedish_newyear_assets.py generated into
// apps/zig/scenes/swedish_newyear/assets_gen.zig, and the scrolltexts copied
// verbatim from screen.js into texts.zig.
import { readFile } from "node:fs/promises";

const DIR = "apps/zig/scenes/swedish_newyear/";
const RAW = "apps/zig/assets/screens/swedish_newyear/";
const nums = (s) => [...s.matchAll(/0x[0-9A-Fa-f]+|\d+/g)].map((m) => Number(m[0]));

export async function loadAssets() {
    const src = await readFile(DIR + "assets_gen.zig", "utf8");
    const A = { img: {} };
    for (const m of src.matchAll(/pub const (\w+) = Img\{ \.w = (\d+), \.h = (\d+), \.bits = (\d+), .*?\.lut = &\[_\]u16\{ ([^}]*) \} \};/g)) {
        const [, name, w, h, bits, lut] = m;
        A.img[name] = { w: +w, h: +h, bits: +bits, lut: nums(lut), data: await readFile(`${RAW}${name}.raw`) };
    }
    const arr = (name) => nums(src.match(new RegExp(`pub const ${name} = [^{]*\\{([^;]*)\\};`))[1].replace(/\[\d+\]u\d+|\[_\]u\d+/g, ""));
    const one = (name) => Number(src.match(new RegExp(`pub const ${name}(?:: u16)? = (\\d+);`))[1]);
    A.colours = arr("colours");
    for (const n of ["rasters_rows", "redraster_rows", "whiteraster_rows", "raster_up_rows", "raster_down_rows", "grey_gid", "clr_level"]) A[n] = arr(n);
    const w = one("MAIN_ROW_COLOURS");
    const ml = arr("main_lut");
    A.mainLut = Array.from({ length: 200 }, (_, y) => ml.slice(y * w, y * w + w));
    A.mainPx = await readFile(RAW + "main.raw");
    const tint = arr("tint_gid");
    const tw = tint.length / 50;
    A.tint = Array.from({ length: 50 }, (_, r) => tint.slice(r * tw, r * tw + tw));
    A.NOISE = one("NOISE_GID");
    const ts = await readFile(DIR + "texts.zig", "utf8");
    A.text = {};
    for (const n of ["menu", "sync1", "tcb2", "tcb2_cylinder", "omega"]) {
        A.text[n] = [...ts.split(`pub const ${n} =`)[1].split(";")[0].matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((m) => m[1].replace(/\\(.)/g, "$1")).join("");
    }
    return A;
}

/// An image's gid at (x, y), or -1 (transparent / outside: drawImage clips).
export function at(img, x, y) {
    if (x < 0 || y < 0 || x >= img.w || y >= img.h) return -1;
    let i;
    if (img.bits === 8) i = img.data[y * img.w + x];
    else {
        const b = img.data[y * ((img.w + 1) >> 1) + (x >> 1)];
        i = x & 1 ? b >> 4 : b & 15;
    }
    return i === 0 ? -1 : img.lut[i];
}

/// The local (font) index, for the tint table.
export function localAt(img, x, y) {
    if (img.bits === 8) return img.data[y * img.w + x];
    const b = img.data[y * ((img.w + 1) >> 1) + (x >> 1)];
    return x & 1 ? b >> 4 : b & 15;
}
