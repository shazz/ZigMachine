#!/usr/bin/env python3
"""Functions of the linked cart that can never be on the stack when kestrel_yield unwinds: Asyncify's removelist.

Why: binaryen's Asyncify instruments every function that MAY unwind (it saves/restores locals and tests the
unwind state around every call and in every loop). It assumes any indirect call may unwind, and every printf
reaches one (musl's FILE write pointer), as does malloc (its out-of-memory message), so SDL_RenderCopy, the
plane presenter and most of klystron's drawing came out instrumented: their pixel loops ran the state checks
on every pixel. Here an indirect call is resolved by its TYPE (wasm traps a call_indirect whose table entry
has another signature, so only table functions of that type can be reached): a function may unwind if it
calls an asyncify.* import (kestrel_yield), calls a function that may unwind, or makes an indirect call of a
type some table function that may unwind has. Every other named function goes in the list; Asyncify leaves
them alone. (-asyncify-ignore-imports: no env/wasi import unwinds, the host functions return.)

  asyncify_leaves.py <wasm-objdump> <cart.raw.wasm> <out.txt>   one name a line
"""
import re
import subprocess
import sys


def objdump(tool, wasm, flag):
    return subprocess.run([tool, flag, wasm], check=True, capture_output=True, text=True).stdout


def module_info(tool, wasm):
    """sig of each function, names, the asyncify imports, the table's functions."""
    sig, name, roots, table = {}, {}, set(), set()
    for line in objdump(tool, wasm, "-x").splitlines():
        m = re.match(r"\s*- func\[(\d+)\] sig=(\d+)(?: <([^>]+)>)?(?: <- (\S+))?", line)
        if m:
            f = int(m.group(1))
            sig[f] = int(m.group(2))
            if m.group(3):
                name[f] = m.group(3)
            if (m.group(4) or "").startswith("asyncify."):
                roots.add(f)
            continue
        m = re.match(r"\s*- elem\[\d+\] = ref\.func:(\d+)", line)
        if m:
            table.add(int(m.group(1)))
    return sig, name, roots, table


def call_graph(tool, wasm):
    """function -> (direct callees, indirect call types)."""
    calls, cur = {}, None
    for line in objdump(tool, wasm, "-d").splitlines():
        m = re.match(r"[0-9a-f]+ func\[(\d+)\]", line)
        if m:
            cur = int(m.group(1))
            calls[cur] = (set(), set())
            continue
        m = re.search(r"\|\s*call (\d+)", line)
        if m and cur is not None:
            calls[cur][0].add(int(m.group(1)))
            continue
        m = re.search(r"\|\s*call_indirect \d+ \(type (\d+)\)", line)
        if m and cur is not None:
            calls[cur][1].add(int(m.group(1)))
    return calls


def may_unwind(sig, roots, table, calls):
    unwinds = set(roots)
    changed = True
    while changed:
        changed = False
        bad_types = {sig[f] for f in table if f in unwinds}
        for f, (direct, types) in calls.items():
            if f not in unwinds and (direct & unwinds or types & bad_types):
                unwinds.add(f)
                changed = True
    return unwinds


def main():
    tool, wasm, out = sys.argv[1:4]
    sig, name, roots, table = module_info(tool, wasm)
    if not roots:
        sys.exit("asyncify_leaves: no asyncify.* import: nothing unwinds?")
    calls = call_graph(tool, wasm)
    unwinds = may_unwind(sig, roots, table, calls)
    leaves = sorted(name[f] for f in calls if f not in unwinds and f in name)
    unnamed = [f for f in calls if f not in name]
    if unnamed:
        sys.exit(f"asyncify_leaves: {len(unnamed)} functions without a name (link without --strip-debug)")
    with open(out, "w") as fh:
        fh.write("\n".join(leaves) + "\n")
    print(f"asyncify_leaves: {len(leaves)} of {len(calls)} functions never unwind ({len(unwinds) - len(roots)} may)")


if __name__ == "__main__":
    main()
