// dune_gen4_headless.mjs, part 2: the keys and the music, after the frames.
// The cart arrives here inside the main part (past every reference frame).

const FADE = 27; // fade.zig's FRAMES
const songAt = (cart, from) => cart.songs.filter(([v]) => v >= from).map(([, n]) => n);

export async function keys(cart, { fail, broke, MAIN_FIRST_VBL, K, outdir }) {
    const first = cart.songs.find(([, n]) => n === "dune_gen4.sndh");
    if (!first || first[0] !== MAIN_FIRST_VBL) fail("music", `Gen4.sndh asked for at ${first?.[0]}, not the main part's first VBL ${MAIN_FIRST_VBL}`);
    else console.log(`  music: dune_gen4.sndh from VBL ${first[0]}, the main part's first`);

    let mark = cart.vbls;
    cart.key(K.space); // the main part's $FFFC02 poll
    cart.run(FADE + 5);
    await cart.shot(`${outdir}/title.ppm`);
    if (songAt(cart, mark).join() !== "none") fail("music", `Space in the main part asked for ${songAt(cart, mark)}, not silence`);
    if (cart.word(160, 100) === 0) fail("keys", "the title picture is not on show after its fade");

    mark = cart.vbls;
    cart.key(K.space);
    cart.run(FADE + 60);
    await cart.shot(`${outdir}/menu.ppm`);
    const menuSong = songAt(cart, mark).join();
    const want = broke === "music" ? "dune_gen4.sndh" : "dune_gen4_menu.sndh";
    if (menuSong !== want) fail("music", `the menu asked for "${menuSong}", not ${want}`);
    else console.log(`  music: none for the title, ${menuSong} once the menu has faded in`);

    cart.key(K.f1);
    cart.run(FADE + 100);
    await cart.shot(`${outdir}/black.ppm`);
    mark = cart.vbls;
    cart.key(K.space);
    cart.run(FADE + 10);
    if (songAt(cart, mark).length) fail("music", `leaving F1 asked for ${songAt(cart, mark)}: the tune runs on`);
    await cart.shot(`${outdir}/menu-again.ppm`);

    cart.key(K.esc);
    const req = cart.demo.pollCartRequest();
    if (req !== -1) fail("keys", `Escape asked for ${req}, not the menu disk (-1)`);
    else console.log("  keys: Space, Space, F1, Space walk the parts; Escape asks for the menu disk");
}
