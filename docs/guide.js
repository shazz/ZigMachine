// docs/ZIGMACHINE_GUIDE.html — the section rail's current marker, the phone
// rail toggle, and the code blocks' Copy button. The tutorial has its own
// (docs/tutorial.js): that page also drives a live machine, this one only reads.
(function () {
    "use strict";
    var rail = document.getElementById("rail");

    function spy() {
        var links = rail.querySelectorAll("a[data-slug]");
        var seen = new IntersectionObserver(function (entries) {
            entries.forEach(function (e) {
                if (!e.isIntersecting) return;
                links.forEach(function (a) {
                    a.setAttribute("aria-current", String(a.dataset.slug === e.target.id));
                });
            });
        }, { rootMargin: "-70px 0px -65% 0px" });
        document.querySelectorAll("main > section[id]").forEach(function (s) { seen.observe(s); });
    }

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

    document.addEventListener("click", function (ev) {
        var t = ev.target.closest && ev.target.closest("button, a");
        if (!t) return;
        if (t.classList.contains("cb-copy")) copy(t);
        else if (t.id === "railtoggle") {
            rail.classList.toggle("open");
            t.setAttribute("aria-expanded", String(rail.classList.contains("open")));
        } else if (t.closest(".rail")) rail.classList.remove("open");
    });

    spy();
})();
