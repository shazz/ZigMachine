// --------------------------------------------------------------------------
// The cart selector: the monitor's "Select" button lists every channel on the
// glass, sorted by name, and running one tunes straight to it — no pressing +
// twenty times.
//
// Host-side only, like the name card (cart-osd.js), and a classic script loaded
// after sealed-loader.js, whose state (channels, currentTag, releaseAll) it
// shares. Launching goes through tuneToChannel, the same guarded path +/- use,
// so the swap race guard, the snow, audio and name card are identical, and
// currentTag is set by the swap itself: +/- step on from the chosen cart.
//
// While it is open it owns the keyboard: capture listeners on window stop every
// key before the loader's body listeners can hand it to a cart.
// --------------------------------------------------------------------------
const cs = { el: null, list: null, track: null, thumb: null, rows: [], cursor: 0, open: false };
const csSwallowed = new Set(); // keys pressed while open: their release is ours too
let csEatClick = false;        // the rest of a gesture that closed the selector

function csRowHtml(c, n) {
    const li = document.createElement("li");
    li.setAttribute("role", "option");
    li.innerHTML = '<span class="cs_num"></span><span class="cs_title"></span><span class="cs_type"></span>';
    li.children[0].textContent = String(n).padStart(2, "0");
    li.children[1].textContent = c.title || c.tag;
    li.children[2].textContent = c.type && c.type !== "unknown" ? c.type : "";
    return li;
}

// The panel, built once from the channel list (fixed for the page's life).
function csBuild(list) {
    const el = document.createElement("div");
    el.className = "cart_select";
    el.setAttribute("role", "dialog");
    el.setAttribute("aria-label", "Select a channel");
    el.innerHTML = '<div class="cs_head"><span>Select channel</span>' +
        '<span class="cs_hint">↑↓ Enter Esc</span></div>' +
        '<div class="cs_body"><ol class="cs_list" role="listbox"></ol><div class="cs_bar">' +
        '<button type="button" class="cs_up" aria-label="Scroll up"></button>' +
        '<div class="cs_track"><div class="cs_thumb"></div></div>' +
        '<button type="button" class="cs_down" aria-label="Scroll down"></button></div></div>';
    Object.assign(cs, { el, list: el.querySelector(".cs_list"),
        track: el.querySelector(".cs_track"), thumb: el.querySelector(".cs_thumb") });
    // Sorted by the name it shows; the number is still the channel's own.
    const sorted = list.map((c, i) => ({ c, n: i + 1 }))
        .sort((a, b) => (a.c.title || a.c.tag).localeCompare(b.c.title || b.c.tag));
    cs.rows = sorted.map(({ c, n }, i) => {
        const li = csRowHtml(c, n);
        li.dataset.tag = c.tag;
        li.addEventListener("click", () => csRun(i));
        li.addEventListener("pointermove", () => csMove(i, false));
        cs.list.appendChild(li);
        return li;
    });
    csWireBar();
    document.querySelector(".stage").appendChild(el);
}

function csRowH() { return cs.rows.length ? cs.rows[0].offsetHeight : 1; }
function csPage() { return Math.max(1, Math.floor(cs.list.clientHeight / csRowH())); }

// Move the cursor; scroll it into view when the keyboard moved it.
function csMove(i, scroll) {
    i = Math.max(0, Math.min(cs.rows.length - 1, i));
    cs.rows[cs.cursor].classList.remove("cursor");
    cs.rows[i].classList.add("cursor");
    cs.rows[i].setAttribute("aria-selected", "true");
    if (i !== cs.cursor) cs.rows[cs.cursor].removeAttribute("aria-selected");
    cs.cursor = i;
    if (!scroll) return;
    const top = cs.rows[i].offsetTop, h = cs.rows[i].offsetHeight, L = cs.list;
    if (top < L.scrollTop) L.scrollTop = top;
    else if (top + h > L.scrollTop + L.clientHeight) L.scrollTop = top + h - L.clientHeight;
}

// The drawn scrollbar follows the list's own scroll position.
function csSyncThumb() {
    const L = cs.list, trackH = cs.track.clientHeight;
    const span = L.scrollHeight - L.clientHeight;
    const h = Math.max(24, Math.round(trackH * L.clientHeight / Math.max(1, L.scrollHeight)));
    cs.thumb.style.height = h + "px";
    cs.thumb.style.top = (span > 0 ? Math.round((trackH - h) * L.scrollTop / span) : 0) + "px";
}

// Arrows scroll a row; the track pages toward the pointer; the thumb drags.
function csWireBar() {
    const by = (n) => { cs.list.scrollTop += n * csRowH(); };
    cs.el.querySelector(".cs_up").addEventListener("click", () => by(-1));
    cs.el.querySelector(".cs_down").addEventListener("click", () => by(1));
    cs.list.addEventListener("scroll", csSyncThumb);
    let drag = null; // { y, top, ratio } while the thumb is held
    cs.track.addEventListener("pointerdown", (e) => {
        e.preventDefault();
        if (e.target !== cs.thumb) { by((e.offsetY < cs.thumb.offsetTop ? -1 : 1) * csPage()); return; }
        const scale = cs.track.getBoundingClientRect().height / cs.track.offsetHeight; // the stage's scale()
        const room = cs.track.clientHeight - cs.thumb.offsetHeight;
        const ratio = (cs.list.scrollHeight - cs.list.clientHeight) / Math.max(1, room) / scale;
        drag = { y: e.clientY, top: cs.list.scrollTop, ratio };
        cs.track.setPointerCapture(e.pointerId);
    });
    cs.track.addEventListener("pointermove", (e) => {
        if (drag) cs.list.scrollTop = drag.top + (e.clientY - drag.y) * drag.ratio;
    });
    const end = () => { drag = null; };
    cs.track.addEventListener("pointerup", end);
    cs.track.addEventListener("pointercancel", end);
}

async function openCartSelect() {
    if (cs.open) return;
    const list = (typeof loadChannels === "function") ? await loadChannels() : null;
    if (!list) return;
    if (!cs.el) csBuild(list);
    releaseAll(); // like a focus loss: the cart must not keep a key it will never see come up
    for (const r of cs.rows) r.classList.toggle("current", r.dataset.tag === currentTag);
    const at = cs.rows.findIndex((r) => r.dataset.tag === currentTag);
    cs.el.classList.add("on");
    cs.open = true;
    csMove(at < 0 ? 0 : at, false);
    // Scroll the running cart to the middle of the list, not just to an edge.
    const r = cs.rows[cs.cursor];
    cs.list.scrollTop = r.offsetTop - (cs.list.clientHeight - r.offsetHeight) / 2;
    csSyncThumb();
}

function closeCartSelect() {
    if (!cs.open) return;
    cs.open = false;
    cs.el.classList.remove("on");
}
function toggleCartSelect() { cs.open ? closeCartSelect() : openCartSelect(); }

// Run the entry: refused (a swap already in flight) leaves the list up.
async function csRun(i) {
    csMove(i, true);
    if (await tuneToChannel(cs.rows[i].dataset.tag)) closeCartSelect();
}

const CS_KEYS = {
    ArrowUp: () => csMove(cs.cursor - 1, true),
    ArrowDown: () => csMove(cs.cursor + 1, true),
    PageUp: () => csMove(cs.cursor - csPage(), true),
    PageDown: () => csMove(cs.cursor + csPage(), true),
    Home: () => csMove(0, true),
    End: () => csMove(cs.rows.length - 1, true),
    Enter: () => csRun(cs.cursor),
    Escape: () => closeCartSelect(),
};

// Capture on window: runs before the loader's listeners (on body, and window's
// bubble phase), and stopImmediatePropagation keeps the key from all of them.
window.addEventListener("keydown", (e) => {
    if (!cs.open) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    csSwallowed.add(e.code);
    if (CS_KEYS[e.key]) CS_KEYS[e.key]();
}, true);
window.addEventListener("keyup", (e) => {
    const ours = csSwallowed.delete(e.code);
    if (!cs.open && !ours) return;
    e.preventDefault();
    e.stopImmediatePropagation();
}, true);

// A press outside closes it, and that whole gesture stops there: it does not
// also change channel, click the picture or fire the touch pad. The full
// virtual keyboard (vkbd.js) is not "outside": it is a keyboard, and its keys
// drive the list like real ones.
window.addEventListener("pointerdown", (e) => {
    csEatClick = false;
    if (!cs.open || cs.el.contains(e.target) || e.target.closest?.(".vkbd")) return;
    closeCartSelect();
    csEatClick = true;
    e.preventDefault();
    e.stopImmediatePropagation();
}, true);
for (const type of ["mousedown", "click"]) {
    window.addEventListener(type, (e) => {
        if (!csEatClick) return;
        if (type === "click") csEatClick = false;
        e.preventDefault();
        e.stopImmediatePropagation();
    }, true);
}

window.openCartSelect = openCartSelect;
window.toggleCartSelect = toggleCartSelect;
