// dune_gen4_headless.mjs, part 2: the walks through the demo, and the music.
//
// The reference frames come in groups, one per visit to a part (mkref.py):
// `intro` is counted in VBLs from the cart's start, every other group in VBLs
// since the key that opened it. A walk replays one Hatari run on a fresh cart,
// pressing each key at the VBL that run did -- so what outlives a visit (the
// menu scroller's place in its text, the BLACK letters' and the skulls' places
// on their path, the HADES logo's walk and wobble) is the same.

const K = { space: 32, esc: 0xe012, f1: 0xe001, f2: 0xe002 };
/// [group, key that ends it, at the group's VBL]; the VBLs are the Hatari
/// run's (prototypes/dune_gen4_re/trace.py on ref4 and ref5).
export const WALKS = {
    ref4: [
        ["intro", K.space, 880], // anywhere in the main part
        ["title", K.space, 200], // anywhere once SingSong would run
        ["menu1", K.f1, 314], // F1 at 3090; the menu's fade at 2776 (its VBL 30 = 2806)
        ["black1", K.space, 658], // Space at 3911, F1's fade at 3253
        ["menu2", K.f1, 339], // F1 at 4425, the fade at 4086
        ["black2", K.space, 468], // Space at 5062, the fade at 4594
        ["menu3", null, 0],
    ],
    ref5: [
        ["", K.space, 880],
        ["", K.space, 200],
        ["", K.f2, 241], // F2 at 2710; the menu's fade at 2469, its VBL 30 at 2499
        ["hades1", K.space, 1723], // F2's VBL 17 at 2727, Space at 4433
        // the fade at 4601 but its VBL 30 at 4632: F2 at 4721 is the 90th
        // menu VBL, and F2's set-up there takes 16 VBLs, not 17 (so 15 more
        // menu VBLs, not 16): F2 one VBL early, the frames one VBL later
        ["", K.f2, 118],
        ["hades2", K.space, 734], // Space at 5454
        ["menu5", null, 0], // the fade at 5630, its VBL 30 at 5661
    ],
};
/// The title's Quartet song is the SNDH's subtune 4 ($3316), started once the
/// fade is over; Space stops it (SingSong's jsr 8) before the menu's tune.
const TUNES = [[0, "dune_gen4.sndh"], [1, "none,dune_gen4_quartet.sndh#4"], [2, "none,dune_gen4_menu.sndh"]];

/// Run one walk; `check(cart, frame)` holds each reference frame.
export function walk(cart, ref, steps, check, { fail, broke }) {
    const songs = [];
    for (const [group, key, at] of steps) {
        const from = cart.vbls;
        for (const f of ref.frames.filter((r) => group && r.part === group)) {
            cart.runTo(from + f.vbl + (broke === "lag" && f.label.startsWith("bounce") ? 1 : 0)
                + (broke === "pixels" && f.label === "main-44" ? 1 : 0));
            check(cart, f);
        }
        if (key === null) break;
        cart.runTo(from + at);
        songs.push(cart.songs.filter(([v]) => v > from).map(([, n]) => n));
        cart.key(key);
    }
    return songs;
}

/// The tunes a walk asked for, visit by visit, and Escape.
export function music(songs, cart, { fail: fail0, broke }) {
    let ok = true;
    const fail = (...a) => { ok = false; fail0(...a); };
    for (const [visit, want0] of TUNES) {
        const want = broke === "music" && visit === 2 ? "dune_gen4.sndh"
            : broke === "quartet" && visit === 1 ? "none,dune_gen4_quartet.sndh#1" : want0;
        if (songs[visit].join() !== want) fail("music", `visit ${visit} asked for "${songs[visit]}", not ${want}`);
    }
    const later = songs.slice(TUNES.length).filter((s) => s.length);
    if (later.length) fail("music", `${later}: the menu tune should run on through F1 and F2`);
    const first = cart.songs.find(([, n]) => n === "dune_gen4.sndh");
    if (first?.[0] !== 437) fail("music", `Gen4.sndh asked for at VBL ${first?.[0]}, not the main part's first (437)`);
    const q = cart.songs.findIndex(([, n]) => n.startsWith("dune_gen4_quartet.sndh"));
    const fadeIn = q > 0 ? cart.songs[q][0] - cart.songs[q - 1][0] : -1; // from the title's stop
    if (fadeIn !== 30) fail("music", `the title's song came ${fadeIn} VBLs into the title, not after its 30-VBL fade`);
    if (ok) console.log("  music: Gen4.sndh from the main part's first VBL, the title's Quartet song once faded in, the poked copy once the menu is up, nothing after");
    cart.key(K.esc);
    const req = cart.demo.pollCartRequest();
    if (req !== -1) fail("keys", `Escape asked for ${req}, not the menu disk (-1)`);
}
