// --------------------------------------------------------------------------
// The full virtual keyboard: an ST-shaped keyboard for touch screens, so a
// phone can play a cart that owns the keyboard (North & South, Joust) or press
// the function keys a demo's menu is built around (Swedish New Year's F1-F5).
//
// Opened by the "Full" button on the touch pad (built by sealed-loader.js, shown
// on touch screens only, never in ?embed). Loaded after the loader and selector.
// Every key is sent as a KeyboardEvent dispatched on <body>: the one path a
// physical key takes. So the loader's own listeners decide what it means (the
// owns-keyboard rule, demo.input / demo.key, heldDirs / heldKeys and their
// release on blur), and the selector's capture listeners still eat keys while
// it is open. Nothing here calls the cart.
//
// Press and hold: keydown on pointerdown, keyup on pointerup/pointercancel, one
// finger per key (multi-touch: hold a direction and fire), and auto-repeat like
// a real keyboard. Shift, Control and Alt are sticky: tap one, then a key; they
// let go after that key. Caps Lock latches until tapped again.
// --------------------------------------------------------------------------
(function () {
    // A key: label, key, what Shift sends (US ST layout; null = the same), code,
    // width in half-key columns.
    const K = (label, key, shifted, code, w) => ({ label, key, shifted: shifted || key, code, w: w || 2 });
    const ch = (c, s) => K(c.toUpperCase(), c, s || c.toUpperCase(), /[a-z]/.test(c) ? "Key" + c.toUpperCase() : PUNCT[c]);
    const PUNCT = { "-": "Minus", "=": "Equal", "`": "Backquote", "[": "BracketLeft", "]": "BracketRight",
        ";": "Semicolon", "'": "Quote", "\\": "Backslash", ",": "Comma", ".": "Period", "/": "Slash" };
    const SHIFT_DIGIT = ")!@#$%^&*(";
    const digit = (d) => K(d, d, SHIFT_DIGIT[+d], "Digit" + d);
    const letters = (s) => [...s].map((c) => ch(c));
    const MOD = { Shift: "shiftKey", Control: "ctrlKey", Alt: "altKey" };

    // The main block is 30 columns wide, the cursor cluster 6; each row fills both.
    const ROWS = [
        [...[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((n) => K("F" + n, "F" + n, null, "F" + n, 3))],
        [K("Esc", "Escape", null, "Escape"), ..."1234567890".split("").map(digit), ch("-", "_"), ch("=", "+"),
            ch("`", "~"), K("⌫", "Backspace", null, "Backspace")],
        [K("Tab", "Tab", null, "Tab", 3), ...letters("qwertyuiop"), ch("[", "{"), ch("]", "}"),
            K("Del", "Delete", null, "Delete", 3)],
        [K("Ctrl", "Control", null, "ControlLeft", 3), ...letters("asdfghjkl"), ch(";", ":"), ch("'", "\""),
            K("Return", "Enter", null, "Enter", 5)],
        [K("Shift", "Shift", null, "ShiftLeft", 3), ch("\\", "|"), ...letters("zxcvbnm"), ch(",", "<"),
            ch(".", ">"), ch("/", "?"), K("Shift", "Shift", null, "ShiftRight", 5)],
        [K("Alt", "Alt", null, "AltLeft", 4), K("Space", " ", null, "Space", 22), K("Caps", "CapsLock", null, "CapsLock", 4)],
    ];
    const CLUSTER = [
        [K("Hide", "", null, "", 6)],
        [K("Help", "Help", null, "Help", 3), K("Undo", "Undo", null, "Undo", 3)],
        [K("Ins", "Insert", null, "Insert"), K("↑", "ArrowUp", null, "ArrowUp"), null],
        [K("←", "ArrowLeft", null, "ArrowLeft"), K("↓", "ArrowDown", null, "ArrowDown"), K("→", "ArrowRight", null, "ArrowRight")],
        [null], [null],
    ];

    const latched = new Set();    // sticky modifiers down now: "Shift", "Control", "Alt"
    let caps = false;
    const pressed = new Map();    // pointerId -> { k, key, el, timer }
    const downCount = new Map();  // key -> fingers on it (two fingers on one key = one press)
    let el = null;

    function send(type, key, code, repeat) {
        const init = { key, code, repeat: !!repeat, bubbles: true, cancelable: true };
        for (const m in MOD) init[MOD[m]] = latched.has(m);
        document.body.dispatchEvent(new KeyboardEvent(type, init));
    }

    // What a key sends now: Shift picks the shifted character, Caps upper-cases letters.
    function keyNow(k) {
        let key = latched.has("Shift") ? k.shifted : k.key;
        if (caps && key.length === 1 && /[a-z]/i.test(key)) {
            key = latched.has("Shift") ? key.toLowerCase() : key.toUpperCase();
        }
        return key;
    }

    function toggleModifier(k) {
        if (k.key === "CapsLock") { caps = !caps; syncLatches(); return; }
        if (!latched.has(k.key)) { latched.add(k.key); send("keydown", k.key, k.code); }
        else { send("keyup", k.key, k.code); latched.delete(k.key); }
        syncLatches();
    }

    function releaseModifiers() {
        for (const m of [...latched]) { send("keyup", m, m + "Left"); latched.delete(m); }
        syncLatches();
    }

    function syncLatches() {
        for (const b of el ? el.querySelectorAll("[data-mod]") : []) {
            b.classList.toggle("latched", b.dataset.mod === "CapsLock" ? caps : latched.has(b.dataset.mod));
        }
    }

    function press(e, k, b) {
        e.preventDefault();
        if (k.label === "Hide") return; // on click: the finger that closes it must not land on the page
        if (MOD[k.key] || k.key === "CapsLock") { toggleModifier(k); return; }
        b.setPointerCapture(e.pointerId);
        const key = keyNow(k);
        const n = downCount.get(key) || 0;
        downCount.set(key, n + 1);
        const p = { k, key, el: b, timer: null };
        pressed.set(e.pointerId, p);
        b.classList.add("down");
        if (n > 0) return; // already down under another finger
        send("keydown", key, k.code);
        // Auto-repeat, like the keyboard a desktop has: a cart without key
        // releases (a menu) steps on while a direction is held.
        p.timer = setTimeout(() => { p.timer = setInterval(() => send("keydown", key, k.code, true), 50); }, 400);
    }

    function release(e) {
        const p = pressed.get(e.pointerId);
        if (!p) return;
        pressed.delete(e.pointerId);
        clearTimeout(p.timer); clearInterval(p.timer);
        const n = downCount.get(p.key) - 1;
        if (n > 0) { downCount.set(p.key, n); return; }
        downCount.delete(p.key);
        if (![...pressed.values()].some((q) => q.el === p.el)) p.el.classList.remove("down");
        send("keyup", p.key, p.k.code);
        if (pressed.size === 0 && latched.size) releaseModifiers(); // one-shot: Shift, then a key
    }

    function keyButton(k) {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "vk_key";
        b.textContent = k.label;
        b.style.gridColumn = "span " + k.w;
        if (k.label.length > 2 && k.key.length > 1) b.classList.add("vk_word");
        if (MOD[k.key] || k.key === "CapsLock") b.dataset.mod = k.key;
        if (k.label === "Hide") { b.classList.add("vk_hide"); b.addEventListener("click", closeKeyboard); }
        b.addEventListener("pointerdown", (e) => press(e, k, b));
        b.addEventListener("pointerup", release);
        b.addEventListener("pointercancel", release);
        b.addEventListener("lostpointercapture", release);
        b.addEventListener("contextmenu", (e) => e.preventDefault()); // a long press is a held key
        return b;
    }

    function build() {
        el = document.createElement("div");
        el.className = "vkbd";
        Object.entries({ role: "group", "aria-label": "Atari ST keyboard" }).forEach(([a, v]) => el.setAttribute(a, v));
        ROWS.forEach((row, r) => {
            for (const k of row) el.appendChild(keyButton(k));
            el.appendChild(Object.assign(document.createElement("span"), { className: "vk_gap" }));
            for (const k of CLUSTER[r]) {
                el.appendChild(k ? keyButton(k) : Object.assign(document.createElement("span"), {
                    style: "grid-column: span " + (CLUSTER[r].length === 1 ? 6 : 2) }));
            }
        });
        document.body.appendChild(el);
    }

    function releaseEverything() {
        for (const id of [...pressed.keys()]) release({ pointerId: id });
        releaseModifiers();
    }

    // While it is open the monitor shrinks to the room above it (index.html's
    // own fit() only knows the width): in landscape the keyboard takes most of
    // the height, and a monitor you would have to scroll to is no use to play.
    function fitStage() {
        const room = window.innerHeight - (isOpen() ? el.offsetHeight : 0);
        const s = Math.min(1, window.innerWidth / 1030, isOpen() ? room / 824 : 1);
        document.documentElement.style.setProperty("--stage-scale", s);
    }
    const isOpen = () => document.documentElement.classList.contains("vkbd-open");

    function openKeyboard() {
        if (!el) build();
        document.documentElement.classList.add("vkbd-open");
        fitStage();
        window.scrollTo(0, 0);
    }
    function closeKeyboard() {
        releaseEverything(); // no key stays down under a keyboard that is gone
        document.documentElement.classList.remove("vkbd-open");
        fitStage();
    }
    function toggleKeyboard() { isOpen() ? closeKeyboard() : openKeyboard(); }
    // After index.html's resize listener, so the height-aware scale wins.
    window.addEventListener("resize", () => { if (isOpen()) fitStage(); });
    // The loader releases every key the cart holds on focus loss; let go of
    // ours too, or a key would light up (and come up again) after the fact.
    window.addEventListener("blur", releaseEverything);

    // The "Full" button, on the touch pad above Esc and Enter.
    const act = document.querySelector(".tpad .act");
    if (act) {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "vk_toggle";
        b.textContent = "Full";
        b.setAttribute("aria-label", "Full keyboard");
        b.addEventListener("pointerdown", (e) => e.preventDefault());
        b.addEventListener("click", toggleKeyboard);
        act.insertBefore(b, act.firstChild);
    }
    window.toggleKeyboard = toggleKeyboard;
})();
