"""The guide page's HTML shell.

Like the tutorial, its CSS and JS are real files: docs/css/docs.css and
docs/css/code.css are shared with the tutorial, docs/css/guide.css and
docs/guide.js are its own, and tools/cache_bust.py stamps all of them.
"""
from __future__ import annotations

TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZigMachine — Programmer's Guide</title>
<meta name="description" content="The ZigMachine reference: video and blitter registers, the sealed HW ABI, the disk and music formats, and the ZigOS / GEM library, generated from the sources.">
<link rel="stylesheet" href="css/docs.css">
<link rel="stylesheet" href="css/code.css">
<link rel="stylesheet" href="css/guide.css">
</head>
<body>
<header class="topbar">
  <a class="wordmark" href="index.html">ZIGMACHINE</a><span class="crumb">Programmer's guide</span>
  <button class="railtoggle" id="railtoggle" aria-expanded="false" aria-controls="rail">Sections</button>
  <div class="spacer"></div>
  <a class="guidelink" href="TUTORIAL.html">Tutorial &rarr;</a>
</header>
<div class="wrap">
  <nav class="rail" id="rail" aria-label="Sections">{rail}</nav>
  <main>
    <section class="hero" id="top">
      <h1>Programmer's guide</h1>
      <ul class="stats">{stats}</ul>
      <div class="intro">{intro}</div>
      <p class="stamp">Generated {date} by tools/gen_docs.py from machine/sdk, libs/zig, rom/gem and docs/*.md</p>
    </section>
    <section class="ref" id="examples">
      <header class="sec-h"><span class="eyebrow">Start</span><h2>Examples<small>six scenes, in Zig</small></h2></header>
      {examples}
    </section>
{sections}
  </main>
</div>
<script src="guide.js"></script>
</body></html>
"""
