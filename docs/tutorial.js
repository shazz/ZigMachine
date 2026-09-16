// docs/TUTORIAL.html — language switching, the step rail, and the live monitor.
//
// The monitor is a REAL machine: an iframe of index.html?demo=<cart>&step=N&embed,
// the same sealed loader the front page uses. Nothing here simulates ZigMachine.
// Audio deliberately stays silent until the reader clicks inside the iframe: a
// click on THIS page is not a gesture in that document, and faking one would be
// both dishonest and ineffective.
(function () {
    "use strict";
    var HTML = document.documentElement;
    var LANGS = ["zig", "c", "rust"];
    var NAMES = { zig: "Zig", c: "C", rust: "Rust" };
    // Step-gated carts: one per language, `?step=N` selects how far to build up.
    var CARTS = { zig: "demo-tutorial-steps.wasm", c: "demo-c-tutorial-steps.wasm",
                  rust: "demo-rust-tutorial-steps.wasm" };
    var LANG_KEY = "zm.tutorial.lang", SEEN_KEY = "zm.tutorial.reached";

    function store(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
    function load(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }

    // ---- language ------------------------------------------------------
    function setLang(lang, remember) {
        if (LANGS.indexOf(lang) < 0) return;
        HTML.dataset.lang = lang;
        if (remember) store(LANG_KEY, lang);
        document.querySelectorAll(".seg").forEach(function (b) {
            b.setAttribute("aria-pressed", String(b.dataset.lang === lang));
        });
        document.querySelectorAll(".run").forEach(function (b) {
            b.textContent = "▶ Run " + NAMES[lang];
        });
        var url = new URL(location.href);
        url.searchParams.set("lang", lang);
        history.replaceState(null, "", url.toString());
        if (monitor.step) boot(monitor.step);   // keep the machine on the shown language
    }

    function setCompare(lang) {
        if (LANGS.indexOf(lang) < 0) { delete HTML.dataset.compare; return; }
        HTML.dataset.compare = lang;
    }

    // ---- the monitor ---------------------------------------------------
    var monitor = { el: document.getElementById("monitor"), step: 0, frame: null };
    var screen = document.getElementById("screen");
    var capt = document.getElementById("capt");
    var stopBtn = document.getElementById("stop");
    var pop = document.getElementById("pop");

    function place(step) {
        // Wide screens keep the machine in its sticky column; narrow ones move the
        // one iframe into the step being run, so code and output stay adjacent.
        if (window.innerWidth >= 1200) {
            document.querySelector(".monitorcol").appendChild(monitor.el);
            return;
        }
        var slot = document.querySelector('.step[data-step="' + step + '"] .run-slot');
        if (slot) slot.appendChild(monitor.el);
    }

    function boot(step) {
        var lang = HTML.dataset.lang || "zig";
        var src = "index.html?demo=" + CARTS[lang] + "&step=" + step + "&embed";
        if (!monitor.frame) {
            monitor.frame = document.createElement("iframe");
            monitor.frame.title = "ZigMachine running the tutorial cart";
            monitor.frame.setAttribute("referrerpolicy", "same-origin");
            screen.textContent = "";
            screen.appendChild(monitor.frame);
        }
        monitor.step = step;
        monitor.frame.src = src;
        monitor.el.classList.add("live");
        capt.textContent = "step " + step + " · " + NAMES[lang] + " — click the screen for sound";
        pop.href = src.replace("&embed", "");
        stopBtn.hidden = pop.hidden = false;
        place(step);
    }

    function stop() {
        if (monitor.frame) { monitor.frame.remove(); monitor.frame = null; }
        monitor.step = 0;
        monitor.el.classList.remove("live");
        screen.innerHTML = '<p class="idle">Press <b>▶ Run</b> on any step to boot it '
            + "here on the real machine.</p>";
        capt.textContent = "idle";
        stopBtn.hidden = pop.hidden = true;
        document.querySelector(".monitorcol").appendChild(monitor.el);
    }

    // ---- the step rail -------------------------------------------------
    var rail = document.getElementById("rail");
    var counterN = document.getElementById("counter-n");

    function markSeen(step) {
        var best = Math.max(Number(load(SEEN_KEY) || 0), step);
        store(SEEN_KEY, String(best));
        document.querySelectorAll(".rail a").forEach(function (a) {
            var m = /^step-(\d+)$/.exec(a.dataset.slug);
            if (m && Number(m[1]) <= best) a.classList.add("seen");
        });
    }

    function spy() {
        var seen = new IntersectionObserver(function (entries) {
            entries.forEach(function (e) {
                if (!e.isIntersecting) return;
                var slug = e.target.id;
                document.querySelectorAll(".rail a").forEach(function (a) {
                    a.setAttribute("aria-current", String(a.dataset.slug === slug));
                });
                var m = /^step-(\d+)$/.exec(slug);
                if (m) { counterN.textContent = m[1]; markSeen(Number(m[1])); }
            });
        }, { rootMargin: "-70px 0px -65% 0px" });
        document.querySelectorAll("section.step, section.plain").forEach(function (s) { seen.observe(s); });
    }

    // ---- copy ----------------------------------------------------------
    function copy(btn) {
        var code = btn.closest(".cb").querySelector("pre").textContent;
        var done = function () {
            btn.textContent = "Copied";
            btn.classList.add("done");
            setTimeout(function () { btn.textContent = "Copy"; btn.classList.remove("done"); }, 1400);
        };
        if (navigator.clipboard) { navigator.clipboard.writeText(code).then(done, function () {}); return; }
        var ta = document.createElement("textarea");
        ta.value = code;
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand("copy"); done(); } catch (e) {}
        ta.remove();
    }

    // ---- wiring --------------------------------------------------------
    document.addEventListener("click", function (ev) {
        var t = ev.target.closest && ev.target.closest("button, a");
        if (!t) return;
        if (t.classList.contains("seg")) { setLang(t.dataset.lang, true); hidePicker(); }
        else if (t.classList.contains("card")) { setLang(t.dataset.lang, true); hidePicker(); }
        else if (t.classList.contains("run")) boot(Number(t.dataset.step));
        else if (t.id === "stop") stop();
        else if (t.classList.contains("cb-copy")) copy(t);
        else if (t.id === "counter") {
            rail.classList.toggle("open");
            t.setAttribute("aria-expanded", String(rail.classList.contains("open")));
        } else if (t.closest(".rail")) rail.classList.remove("open");
    });

    document.getElementById("compare").addEventListener("change", function () { setCompare(this.value); });

    document.addEventListener("keydown", function (ev) {
        if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
        if (/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) return;
        var k = ev.key.toLowerCase();
        if (k === "z" || k === "c" || k === "r") setLang(k === "r" ? "rust" : k, true);
        else if (k === "[" || k === "]") hop(k === "]" ? 1 : -1);
    });

    function hop(dir) {
        var secs = [].slice.call(document.querySelectorAll("section.step, section.plain"));
        var cur = 0;
        secs.forEach(function (s, i) { if (s.getBoundingClientRect().top <= 80) cur = i; });
        var next = secs[Math.max(0, Math.min(secs.length - 1, cur + dir))];
        if (next) next.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    function hidePicker() {
        var p = document.getElementById("picker");
        if (p) p.hidden = true;
    }

    window.addEventListener("pagehide", stop);

    // ---- boot ----------------------------------------------------------
    var fromUrl = new URLSearchParams(location.search).get("lang");
    var saved = load(LANG_KEY);
    setLang(fromUrl || saved || "zig", Boolean(fromUrl));
    if (!saved && !fromUrl) document.getElementById("picker").hidden = false;
    markSeen(Number(load(SEEN_KEY) || 0));
    spy();
})();
