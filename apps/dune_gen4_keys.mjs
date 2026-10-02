// dune_gen4_headless.mjs, part 2: the walk through the demo, and the music.
//
// The reference frames come in groups, one per visit to a part (mkref.py):
// `intro` is counted in VBLs from the cart's start, every other group in VBLs
// since the key that opened it. Between groups the walk presses the key at the
// VBL the Hatari run did -- so state that outlives a visit (the menu scroller's
// place in its text, the BLACK letters' places on their path) is the same.

const K = { space: 32, esc: 0xe012, f1: 0xe001 };
/// [group, key that ends it, at the group's VBL]: Hatari ref4's VBL counts
/// (prototypes/dune_gen4_re/trace.py), from the part's start to the key.
export const WALK = [
    ["intro", K.space, 880], // anywhere in the main part
    ["title", K.space, 200], // anywhere once SingSong would run
    ["menu1", K.f1, 314], // F1 at 3090, the menu's first VBL 2806 = its VBL 30
    ["black1", K.space, 658], // Space at 3911, the fade at 3253 = VBL 0
    ["menu2", K.f1, 339], // F1 at 4425, the fade at 4086
    ["black2", K.space, 468], // Space at 5062, the fade at 4594
    ["menu3", null, 0],
];
const TUNES = [["intro", "dune_gen4.sndh"], ["title", "none"], ["menu1", "dune_gen4_menu.sndh"]];

/// Run the walk; `check(cart, frame)` holds each reference frame.
export function walk(cart, ref, check, { fail, broke }) {
    const songs = {};
    for (const [group, key, at] of WALK) {
        const from = cart.vbls;
        for (const f of ref.frames.filter((r) => r.part === group)) {
            cart.runTo(from + f.vbl + (broke === "lag" && f.label.startsWith("bounce") ? 1 : 0)
                + (broke === "pixels" && f.label === "main-44" ? 1 : 0));
            check(cart, f);
        }
        if (key === null) break;
        cart.runTo(from + at);
        songs[group] = cart.songs.filter(([v]) => v > from).map(([, n]) => n);
        cart.key(key);
    }
    music(songs, cart, { fail, broke });
}

function music(songs, cart, { fail: fail0, broke }) {
    let ok = true;
    const fail = (...a) => { ok = false; fail0(...a); };
    for (const [group, want0] of TUNES) {
        const want = broke === "music" && group === "menu1" ? "dune_gen4.sndh" : want0;
        if (songs[group].join() !== want) fail("music", `${group} asked for "${songs[group]}", not ${want}`);
    }
    const later = Object.entries(songs).filter(([g, s]) => !TUNES.some(([t]) => t === g) && s.length);
    if (later.length) fail("music", `${later.map(([g, s]) => `${g}: ${s}`)}: the menu tune should run on`);
    const first = cart.songs.find(([, n]) => n === "dune_gen4.sndh");
    if (first?.[0] !== 437) fail("music", `Gen4.sndh asked for at VBL ${first?.[0]}, not the main part's first (437)`);
    if (ok) console.log("  music: Gen4.sndh from the main part's first VBL, silence for the title, the poked copy once the menu is up, nothing after");
    cart.key(K.esc);
    const req = cart.demo.pollCartRequest();
    if (req !== -1) fail("keys", `Escape asked for ${req}, not the menu disk (-1)`);
}
