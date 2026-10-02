"""The cycles sim (plan step 0b-ii): the ZigMachine SoC in Verilator with 32 MiB
of main RAM, the CPU reset straight into it and no BIOS.

    uv run python -m soc.cycles_sim     # -> build/soc_cycles: obj_dir/Vsim + generated/csr.h

The program is NOT baked into the model. Main RAM is declared with a one-word
init, which makes LiteX emit `$readmemh("<name>.init", ...)`: Verilator reads that
file from the run directory at time 0, so one Verilated binary serves every cart
and tools/cycles_run.py only writes the file. Rebuilding the model per cart would
cost minutes; writing the file costs nothing.

The CPU is the same `standard` VexRiscv (rv32im, 4 KiB I$ + 4 KiB D$) as the
board SoC. Only the memory differs: an on-chip SRAM that answers in one cycle,
where the board has DDR. ZMCycles counts the bus traffic so the report can say
what that difference costs, and ZMMemTiming (soc/zm_memtiming.py) puts the
board's latencies back on the main-RAM path, configured at run time: with its
all-zero default the model is the one-cycle RAM.

    uv run python -m soc.cycles_sim --core build/vexgen/VexRiscv_I16D4.v --out build/soc_mem/I16D4

builds the same SoC around another VexRiscv netlist (vexgen/, same ports).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path

from litex.build.sim import SimPlatform
from litex.build.sim.config import SimConfig
from litex.build.sim.platform import SimFinish
from litex.soc.integration.builder import Builder
from litex.soc.integration.soc import SoCRegion
from litex.soc.interconnect import wishbone

from soc import litex_compat
from soc.zigmachine_soc import SIM_IO, SYS_CLK_SIM, ZigMachineSoC, _SimCRG
from soc.zm_cycles import ZMCycles
from soc.zm_memtiming import ZMMemTiming

FPGA = Path(__file__).resolve().parent.parent
OUT = FPGA / "build/soc_cycles"
MAIN_RAM = 0x40000000  # LiteX's default main_ram origin; cycles/link.ld agrees
MAIN_RAM_SIZE = 32 << 20  # 7 MiB of wasm memory + three translated modules + heap


def add_main_ram(soc: ZigMachineSoC, platform: SimPlatform) -> None:
    """main_ram as LiteX's add_ram makes it, with ZMMemTiming between bus and SRAM."""
    bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
    sram_bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
    soc.main_ram = wishbone.SRAM(MAIN_RAM_SIZE, bus=sram_bus, init=[0], name="main_ram")
    soc.main_ram_timing = ZMMemTiming(bus, sram_bus)
    soc.bus.add_slave("main_ram", bus, SoCRegion(origin=MAIN_RAM, size=MAIN_RAM_SIZE, mode="rwx"))
    platform.add_source(str(FPGA / "rtl/sim/zm_memcfg.v"))


def make_soc(core: Path | None = None) -> ZigMachineSoC:
    platform = SimPlatform("SIM", SIM_IO)
    soc = ZigMachineSoC(
        platform, SYS_CLK_SIM, "sys", rom_size=0, main_ram_size=0, uart_name="sim", cpu_reset_address=MAIN_RAM
    )
    add_main_ram(soc, platform)
    if core is not None:
        soc.cpu.use_external_variant(str(core))
    soc.crg = _SimCRG(platform.request("sys_clk"))
    soc.zm_cycles = ZMCycles(soc.cpu.ibus, soc.cpu.dbus)
    soc.sim_finish = SimFinish()
    return soc


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--core", type=Path, help="a VexRiscv netlist with the standard ports (default: LiteX's)")
    ap.add_argument("--out", type=Path, default=OUT, help="build directory")
    a = ap.parse_args()
    out = a.out if a.out.is_absolute() else FPGA / a.out
    litex_compat.install()
    soc = make_soc(a.core.resolve() if a.core else None)
    sim_config = SimConfig()
    sim_config.add_clocker("sys_clk", freq_hz=SYS_CLK_SIM)
    sim_config.add_module("serial2console", "serial")
    builder = Builder(soc, output_dir=str(out), compile_software=False)
    builder.build(sim_config=sim_config, run=False, build=True, opt_level="O3")
    # LiteX only writes build_sim.sh here; it compiles on `run`, which would also run it.
    # Its Makefiles append to CFLAGS/LDFLAGS, so the env carries tools/setup.sh's headers.
    deps = FPGA / ".tools/simdeps/usr"
    env = dict(os.environ, CFLAGS=f"-I{deps}/include", LDFLAGS=f"-L{deps}/lib/x86_64-linux-gnu")
    subprocess.run(["bash", "build_sim.sh"], cwd=out / "gateware", env=env, check=True)
    init = sorted((out / "gateware").glob("*main_ram*.init"))
    if len(init) != 1:
        raise SystemExit(f"cycles_sim: expected one main_ram .init file, found {init}")
    # tools/cycles_run.py needs the name the model reads and the RAM geometry.
    meta = {"init": init[0].name, "main_ram": MAIN_RAM, "main_ram_size": MAIN_RAM_SIZE}
    (out / "cycles_sim.json").write_text(json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    main()
