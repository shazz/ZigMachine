"""The guide page's CSS and HTML shell."""
from __future__ import annotations

CSS = """
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body { margin: 0; background: #0e1016; color: #d7dbe6; font: 15px/1.6 system-ui, sans-serif; }
header { padding: 32px 40px; background: linear-gradient(135deg, #1a1f2e, #0e1016); border-bottom: 1px solid #2a3142; }
h1 { margin: 0 0 6px; font-size: 26px; letter-spacing: .5px; }
.sub { color: #8b93a7; font-size: 13px; }
.wrap { display: flex; gap: 28px; max-width: 1200px; margin: 0 auto; padding: 28px 40px; }
nav { position: sticky; top: 20px; align-self: flex-start; min-width: 210px; display: flex; flex-direction: column; gap: 4px; }
nav a { color: #9aa4bd; text-decoration: none; padding: 5px 10px; border-radius: 6px; font-size: 13px; }
nav a:hover { background: #1a2030; color: #fff; }
nav a.ext { color: #7dff9b; border: 1px solid #2c4a37; margin-bottom: 6px; }
nav a.ext:hover { background: #172b20; }
main { flex: 1; min-width: 0; }
h2 { margin: 34px 0 14px; font-size: 19px; color: #7dd3fc; border-bottom: 1px solid #232a3a; padding-bottom: 6px; }
h3 { margin: 20px 0 8px; font-size: 15px; color: #fbbf72; }
.item { padding: 10px 0; border-bottom: 1px solid #191e2b; }
.sig { display: block; color: #a5f3c0; font: 13px/1.5 ui-monospace, monospace; white-space: pre-wrap; }
.doc { color: #9aa4bd; font-size: 13.5px; margin-top: 4px; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #1c2230; vertical-align: top; }
th { color: #7dd3fc; font-weight: 600; }
td code, .sig, code { color: #a5f3c0; }
pre.code, main pre { background: #12151f; border: 1px solid #232a3a; border-radius: 8px; padding: 14px 16px;
           overflow-x: auto; font: 12.5px/1.5 ui-monospace, monospace; color: #cdd6e6; }
/* markdown-rendered sections (FLOPPY_DISK.md): give its own headings the guide look */
main h1 { font-size: 21px; color: #7dd3fc; border-bottom: 1px solid #232a3a; padding-bottom: 6px; margin: 30px 0 14px; }
main pre code { background: none; padding: 0; }
.intro { background: #12151f; border: 1px solid #232a3a; border-radius: 8px; padding: 16px 18px; margin-bottom: 8px; }
code { background: #1a2030; padding: 1px 5px; border-radius: 4px; }
/* Phones: the nav moves above the content and wide blocks scroll on their own. */
@media (max-width: 800px) {
  .wrap { flex-direction: column; gap: 12px; padding: 16px; }
  nav { position: static; flex-direction: row; flex-wrap: wrap; min-width: 0; }
  header { padding: 16px; }
  table { display: block; overflow-x: auto; }
  .sig { overflow-wrap: anywhere; }
}
"""

TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZigMachine — Programmer's Guide</title>
<style>{css}</style></head>
<body>
<header>
  <h1>ZigMachine — Programmer's Guide</h1>
  <div class="sub">Generated {date} by tools/gen_docs.py · {counts}</div>
</header>
<div class="wrap">
  <nav><a class="ext" href="TUTORIAL.html">Tutorial &rarr;</a><a href="#top">Overview</a><a href="#examples">Examples</a>{nav}</nav>
  <main>
    <section id="top"><h2>Overview</h2><div class="intro">{intro}</div></section>
    <section id="examples"><h2>Examples</h2>{examples}</section>
    {sections}
  </main>
</div>
</body></html>
"""
