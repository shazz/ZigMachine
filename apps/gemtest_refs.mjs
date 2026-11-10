// gemtest_shots.mjs --assets: which images of Matt's LOCAL GEM assets page (manifest.json: the TOS 4 /
// MultiTOS object trees, icons, fonts) a GEMTEST component is compared with, matched by the manifest's
// file names (TOS 4: aes340_tos4). A pattern with {v} is per mode, the ST variant of that mode's screen
// (st_low, st_medium, st_high for the desk); one without is the same for all three. Nothing is copied:
// the sheet links the images where they are (relative to the shots' directory).
import { readFile } from "node:fs/promises";
import path from "node:path";

const C = "aes340_tos4/components/{v}/";
const MATCH = {
    windows: [`${C}windows/window_all_gadgets`],
    menus: [`${C}menus/admenu_bar`, `${C}menus/admenu_options`],
    drop_test: [`${C}menus/admenu_file`],
    drop_menus: [`${C}menus/admenu_options`],
    drop_alerts: [`${C}menus/admenu_view`],
    dialogs: [`${C}dialogs/mnsetpre`, `${C}dialogs/addinfo`, `${C}dialogs/adfilein`],
    alerts: [`${C}dialogs/alert`, "aes340_tos4/gem/images/notebb", "aes340_tos4/gem/images/quesbb", "aes340_tos4/gem/images/stopbb"],
    alert_note1: [`${C}alerts/gem_alrt00cr`, "aes340_tos4/gem/images/notebb"],
    alert_wait2: [`${C}alerts/gem_alrt01cr`, "aes340_tos4/gem/images/quesbb"],
    alert_stop3: [`${C}alerts/gem_alrt02cr`, "aes340_tos4/gem/images/stopbb"],
    alert_none1: [],
    files: [`${C}dialogs/selector`],
    fsel_a: [`${C}dialogs/selector`],
    fsel_c: [`${C}dialogs/selector`],
    fsel_c_txt: [`${C}dialogs/selector`],
    text: ["vdi/fonts/8x8_system_font_sample", "vdi/fonts/8x16_system_font_sample", "vdi/fonts/6x6_system_font_sample"],
    icons: ["aes340_tos4/desktop/icons/"],
    modes: [`${C}dialogs/mnsetvid`, `${C}dialogs/sscreen`, `${C}dialogs/screen`],
    desktop: [`${C}windows/desktop_directory_icons`, `${C}menus/admenu_bar`, "aes340_tos4/desktop/icons/"],
};
const MAX = 8;
const VARIANTS = ["st_low", "st_medium", "st_high"];

/** {component: [low, medium, desk, any]}: lists of image paths relative to `out`. */
export async function references(assets, out, components) {
    const manifest = JSON.parse(await readFile(path.join(assets, "manifest.json"), "utf8"));
    const files = manifest.map((e) => e.file);
    const rel = (f) => path.relative(path.resolve(out), path.resolve(assets, f));
    const pick = (pats) => {
        const found = [];
        for (const pat of pats) for (const f of files) if (f.includes(pat) && !found.includes(f) && found.length < MAX) found.push(f);
        return found.map(rel);
    };
    const refs = {};
    for (const c of components) {
        const pats = MATCH[c] ?? [];
        const per = pats.filter((p) => p.includes("{v}"));
        refs[c] = [...VARIANTS.map((v) => pick(per.map((p) => p.replace("{v}", v)))), pick(pats.filter((p) => !p.includes("{v}")))];
    }
    return refs;
}
