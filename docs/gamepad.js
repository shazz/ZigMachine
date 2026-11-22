// Gamepads for the browser host (R83: two joysticks, one per player). The Gamepad API is polled
// once a frame (docs/sealed-loader.js loop): the first connected pad is player 1 and sends the
// cart's input()/inputRelease(), the second is player 2 and sends input2()/inputRelease2() when
// the cart exports both (docs/hardware/HW_API.md "Player 2 input"); a cart without them gets the two pads
// merged into input(), exactly the one-stick behaviour. The direction codes are the keyboard's:
// 0 up, 1 down, 2 left, 3 right, 5 fire. The KESTREL board does the same from evdev (fpga/glass).
//
// A classic script exposing ZMPad (the page has no module for it); apps/gamepad_check.mjs runs it
// in a vm with scripted pads.
const ZMPad = (function () {
    const UP = 0, DOWN = 1, LEFT = 2, RIGHT = 3, FIRE = 5;
    const DEAD = 0.5; // an analog stick counts past half its throw; a worn stick rests off-centre
    const FIRE_BUTTONS = [0, 1, 2, 3]; // the "standard" mapping's A, B, X, Y

    // The direction codes one pad holds now (a Gamepad: the standard mapping's d-pad buttons 12-15,
    // else the first stick or a hat on axes 6/7).
    function held(gp) {
        const out = new Set();
        const b = (i) => !!(gp.buttons && gp.buttons[i] && gp.buttons[i].pressed);
        const a = (i) => (gp.axes && gp.axes[i]) || 0;
        if (b(12) || a(1) < -DEAD || a(7) < -DEAD) out.add(UP);
        if (b(13) || a(1) > DEAD || a(7) > DEAD) out.add(DOWN);
        if (b(14) || a(0) < -DEAD || a(6) < -DEAD) out.add(LEFT);
        if (b(15) || a(0) > DEAD || a(6) > DEAD) out.add(RIGHT);
        if (FIRE_BUTTONS.some(b)) out.add(FIRE);
        return out;
    }

    const state = { demo: null, now: [new Set(), new Set()] };

    // Send the edges of `now` against what `before` held, as `down(code)` / `up(code)`.
    function edges(before, now, down, up) {
        for (const c of now) if (!before.has(c)) down(c);
        for (const c of before) if (!now.has(c)) up(c);
    }

    // One frame: `pads` is navigator.getGamepads() (null entries and gaps are skipped), `demo` the
    // cart's exports. A new `demo` (a cart swap) starts from nothing held: the new cart never saw
    // the old presses, and a pad still held is sent to it as a fresh press.
    function poll(pads, demo) {
        if (state.demo !== demo) state.demo = demo, state.now = [new Set(), new Set()];
        const live = Array.from(pads || []).filter((p) => p && p.connected).sort((x, y) => x.index - y.index);
        const next = [live[0] ? held(live[0]) : new Set(), live[1] ? held(live[1]) : new Set()];
        const own = !!(demo.input2 && demo.inputRelease2);
        const inp = (c) => demo.input && demo.input(c);
        const rel = (c) => demo.inputRelease && demo.inputRelease(c);
        if (own) {
            edges(state.now[0], next[0], inp, rel);
            edges(state.now[1], next[1], (c) => demo.input2(c), (c) => demo.inputRelease2(c));
        } else {
            const union = (s) => new Set([...s[0], ...s[1]]);
            edges(union(state.now), union(next), inp, rel);
        }
        state.now = next;
    }

    // Focus loss: let go of everything the pads hold (the page's own releaseAll does the keys).
    function release(demo) {
        poll([], demo);
    }

    return { held, poll, release, UP, DOWN, LEFT, RIGHT, FIRE };
})();
