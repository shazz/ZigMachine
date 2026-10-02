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
what that difference costs.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from litex.build.sim import SimPlatform
from litex.build.sim.config import SimConfig
from litex.build.sim.platform import SimFinish
from litex.soc.integration.builder import Builder

from soc import litex_compat
from soc.zigmachine_soc import SIM_IO, SYS_CLK_SIM, ZigMachineSoC, _SimCRG
from soc.zm_cycles import ZMCycles

FPGA = Path(__file__).resolve().parent.parent
OUT = FPGA / "build/soc_cycles"
MAIN_RAM = 0x40000000  # LiteX's default main_ram origin; cycles/link.ld agrees
MAIN_RAM_SIZE = 32 << 20  # 7 MiB of wasm memory + three translated modules + heap


def make_soc() -> ZigMachineSoC:
    platform = SimPlatform("SIM", SIM_IO)
    soc = ZigMachineSoC(
        platform,
        SYS_CLK_SIM,
        "sys",
        rom_size=0,
        main_ram_size=MAIN_RAM_SIZE,
        uart_name="sim",
        cpu_reset_address=MAIN_RAM,
        integrated_main_ram_init=[0],
    )
    soc.crg = _SimCRG(platform.request("sys_clk"))
    soc.zm_cycles = ZMCycles(soc.cpu.ibus, soc.cpu.dbus)
    soc.sim_finish = SimFinish()
    return soc


def main() -> None:
    litex_compat.install()
    soc = make_soc()
    sim_config = SimConfig()
    sim_config.add_clocker("sys_clk", freq_hz=SYS_CLK_SIM)
    sim_config.add_module("serial2console", "serial")
    builder = Builder(soc, output_dir=str(OUT), compile_software=False)
    builder.build(sim_config=sim_config, run=False, build=True, opt_level="O3")
    # LiteX only writes build_sim.sh here; it compiles on `run`, which would also run it.
    # Its Makefiles append to CFLAGS/LDFLAGS, so the env carries tools/setup.sh's headers.
    deps = FPGA / ".tools/simdeps/usr"
    env = dict(os.environ, CFLAGS=f"-I{deps}/include", LDFLAGS=f"-L{deps}/lib/x86_64-linux-gnu")
    subprocess.run(["bash", "build_sim.sh"], cwd=OUT / "gateware", env=env, check=True)
    init = sorted((OUT / "gateware").glob("*main_ram*.init"))
    if len(init) != 1:
        raise SystemExit(f"cycles_sim: expected one main_ram .init file, found {init}")
    # tools/cycles_run.py needs the name the model reads and the RAM geometry.
    meta = {"init": init[0].name, "main_ram": MAIN_RAM, "main_ram_size": MAIN_RAM_SIZE}
    (OUT / "cycles_sim.json").write_text(json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    main()
