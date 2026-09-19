"""The tutorial page's HTML shell.

Unlike the guide, the tutorial's CSS and JS are real files (docs/css/tutorial.css,
docs/tutorial.js) rather than Python strings: the page is interactive, so the
behaviour belongs in a file a browser devtool can debug, and tools/cache_bust.py
stamps both with a content hash for free.
"""
from __future__ import annotations

LANG_NAMES = [("zig", "Zig"), ("c", "C"), ("rust", "Rust")]

# Applied before first paint, so the page never flashes three copies of every step.
PREPAINT = """<script>
(function () {
  var l = null;
  try { l = localStorage.getItem("zm.tutorial.lang"); } catch (e) {}
  document.documentElement.dataset.lang = l || "zig";
})();
</script>"""

TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZigMachine — Tutorial</title>
<meta name="description" content="Write your first ZigMachine screen, step by step, in Zig, C or Rust — running live on the real machine.">
<link rel="stylesheet" href="css/tutorial.css">
<link rel="stylesheet" href="css/tutorial-code.css">
{prepaint}
</head>
<body>
<header class="topbar">
  <a class="wordmark" href="index.html">ZIGMACHINE</a><span class="crumb">TUTORIAL</span>
  <button class="counter" id="counter" aria-expanded="false" aria-controls="rail">
    <span id="counter-n">1</span> / {nsteps}
  </button>
  <div class="spacer"></div>
  <div class="langpick" role="group" aria-label="Language">{langpick}</div>
  <label class="comparepick">compare
    <select id="compare" aria-label="Compare with a second language">{comparepick}</select>
  </label>
  <a class="guidelink" href="ZIGMACHINE_GUIDE.html">Reference &rarr;</a>
</header>
<div class="wrap">
  <nav class="rail" id="rail" aria-label="Steps">{rail}</nav>
  <main>
    <section class="intro" id="intro">
      <h1>{title}</h1>
      {intro}
      <div class="picker" id="picker" hidden>
        <p class="picker-q">Which language do you want to read this in?
          <span class="picker-sub">You can switch any time.</span></p>
        <div class="picker-cards">{cards}</div>
      </div>
    </section>
{sections}
  </main>
  <aside class="monitorcol" aria-label="The machine">
    <div class="monitor" id="monitor">
      <div class="screen" id="screen">
        <p class="idle">Press <b>&#9654; Run</b> on any step to boot it here on the real machine.</p>
      </div>
      <div class="caption">
        <span class="dot" id="dot" aria-hidden="true"></span>
        <span class="capt" id="capt">idle</span>
        <button class="stop" id="stop" hidden>&#9632; Stop</button>
        <a class="pop" id="pop" href="index.html?demo=demo-tutorial.wasm" hidden>&#8599;</a>
      </div>
    </div>
  </aside>
</div>
<script src="tutorial.js"></script>
</body></html>
"""


def langpick() -> str:
    return "".join(
        f'<button class="seg" data-lang="{k}" aria-pressed="false">{n}</button>'
        for k, n in LANG_NAMES
    )


def comparepick() -> str:
    opts = '<option value="">—</option>'
    return opts + "".join(f'<option value="{k}">{n}</option>' for k, n in LANG_NAMES)
