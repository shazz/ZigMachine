package zm

// --dTcm (fpga/review/BARD_BRAM_STUDY.md): a tightly coupled data memory on the D-bus,
// DBusCachedPlugin's own TightlyCoupledDataPort. A load or store whose address falls in
// the window never reaches the D$ or the Wishbone bus: the address leaves in EXECUTE and
// the word is read in MEMORY, so a hit costs what a D$ hit costs and there is no miss.
// The core exports the port as `dTcm_*` (enable, address, write_enable, write_data,
// write_mask, read_data); the SoC puts a synchronous BRAM behind it (soc/zm_sound_tcm.py),
// which may be smaller than the window (it then aliases inside it).

import spinal.core._
import vexriscv.plugin.{DBusCachedPlugin, TightlyCoupledDataPortParameter}

object ZmTcm {
  val BASE = 0x9e000000L // bit 31 set (an I/O address to the D$), outside every BARD window
  val WINDOW_LOG2 = 18 // 256 KiB of address decode: the BRAM behind it sets the real size

  def hit(address: UInt): Bool =
    address(31 downto WINDOW_LOG2) === U(BASE >> WINDOW_LOG2, 32 - WINDOW_LOG2 bits)

  def add(p: DBusCachedPlugin): DBusCachedPlugin = {
    p.newTightlyCoupledPort(TightlyCoupledDataPortParameter("dTcm", hit))
    p
  }
}
