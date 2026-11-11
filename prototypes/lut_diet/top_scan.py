"""Scan the LiteX top-level netlist and CSR map of a board build (where the glue's LUTs go)."""
from __future__ import annotations

import json
import re
import sys
from collections import Counter
from pathlib import Path

ref = Path(sys.argv[1])
j = json.load(open(ref / "csr.json"))
regs = j.get("csr_registers", {})
print("csr registers:", len(regs))
print(Counter(k.split("_")[0] for k in regs).most_common())
print("csr_bases", j.get("csr_bases"))
print("constants", {k: v for k, v in j.get("constants", {}).items() if "csr" in k.lower() or "width" in k.lower()})
v = open(ref / "platform_z7.v").read()
print("csrbank instances:", sorted(set(re.findall(r"builder_csrbank\d+", v))))
muls = [m for m in re.findall(r"^assign .*[^/]\*[^/].*$", v, re.M)]
print("multiplies at top:", len(muls))
for m in muls[:30]:
    print("  ", m[:160])
# always blocks with multiplies
for m in re.findall(r"^\s*\w+ <= .*[^/]\*[^/].*$", v, re.M)[:20]:
    print("  seq", m.strip()[:160])
