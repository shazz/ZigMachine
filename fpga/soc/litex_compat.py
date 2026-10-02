"""A shim between LiteX 2024.12 and the pinned migen (git), needed only when
Verilog is actually written (the sims), never by `make soc`.

migen's SyncFIFO now asks for a write-only memory port (`read_capable=False`, so
`dat_r is None`) in READ_FIRST mode. LiteX's own memory emitter
(litex/gen/fhdl/memory.py) still assigns every port's `dat_r`, and fails on the
None. The shim gives such a port a named, declared, unused read signal, which is
exactly what migen emitted before the change. Nothing reads it.
"""

from __future__ import annotations

import importlib
from typing import Any

from migen import Signal

# `import litex.gen.fhdl.memory as m` resolves to migen.fhdl (litex.gen re-exports
# migen's names), so the module is fetched by its full name.
litex_memory = importlib.import_module("litex.gen.fhdl.memory")

# litex.gen.fhdl.memory's generator takes migen's untyped Memory and namespace.
Untyped = Any

_original = litex_memory._memory_generate_verilog


def _generate(name: str, memory: Untyped, namespace: Untyped, add_data_file: Untyped) -> str:
    decls = ""
    for n, port in enumerate(memory.ports):
        if port.dat_r is None:
            unused = f"{namespace.get_name(memory)}_wonly{n}"
            port.dat_r = Signal(memory.width, name_override=unused)
            decls += f"wire [{memory.width - 1}:0] {unused}; // write-only port, see soc/litex_compat.py\n"
    return decls + _original(name, memory, namespace, add_data_file)


def install() -> None:
    """Idempotent. LiteX imports the generator at each call, so the module attribute is the hook."""
    litex_memory._memory_generate_verilog = _generate
