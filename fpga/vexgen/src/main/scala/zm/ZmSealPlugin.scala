package zm

// The seal (fpga/rtl/seal/README.md): the cart CPU's bus windows, checked in the
// core's own memory-translation slot so a forbidden access is a PRECISE trap and
// never reaches the bus.
//
// It replaces StaticMemoryTranslatorPlugin (same physical address, same ioRange)
// and only fills in allowRead/allowWrite/allowExecute, from rtl/seal/zm_seal.v
// instantiated as a black box: the window map lives in Verilog, once, where the
// CXXRTL testbench checks it. The privilege is the core's (CsrPlugin with
// userGen), so the cart cannot forge it: only a trap enters M and only mret
// leaves it, and both flush the pipeline, so every access is judged with the
// privilege of the instruction that made it.
//
// The data port says isPaging for every access. VexRiscv's DataCache ignores a
// translation's permissions on its uncached (IO) path unless the translation is
// paging (DataCache.scala: the bypass branch only raises accessError on a bus
// error), so without it a U load or store to the CSR bus would go out. With it,
// every data-side denial is a load/store PAGE fault (mcause 13/15), cached or
// not, and 5/7 stay what they mean: a real bus error. tests/seal/ caught this.

import spinal.core._
import vexriscv._
import vexriscv.plugin._

import scala.collection.mutable.ArrayBuffer

class ZmSeal extends BlackBox {
  setDefinitionName("zm_seal")
  val io = new Bundle {
    val addr = in UInt (32 bits)
    val user = in Bool ()
    val r, w, x = out Bool ()
  }
  noIoPrefix()
}

class ZmSealPlugin(ioRange: UInt => Bool) extends Plugin[VexRiscv] with MemoryTranslator {
  val ports = ArrayBuffer[(MemoryTranslatorBus, Boolean)]()

  override def newTranslationPort(priority: Int, args: Any): MemoryTranslatorBus = {
    val bus = MemoryTranslatorBus(MemoryTranslatorBusParameter(wayCount = 0))
    ports += ((bus, priority == MemoryTranslatorPort.PRIORITY_DATA))
    bus
  }

  override def setup(pipeline: VexRiscv): Unit = {}

  override def build(pipeline: VexRiscv): Unit = {
    val privilege = pipeline.service(classOf[PrivilegeService])
    pipeline plug new Area {
      for ((bus, isData) <- ports) {
        val seal = new ZmSeal
        val address = bus.cmd.last.virtualAddress
        seal.io.addr := address
        seal.io.user := privilege.isUser()
        bus.rsp.physicalAddress := address
        bus.rsp.isIoAccess := ioRange(address)
        bus.rsp.isPaging := Bool(isData)
        bus.rsp.exception := False
        bus.rsp.refilling := False
        bus.rsp.allowRead := seal.io.r
        bus.rsp.allowWrite := seal.io.w
        bus.rsp.allowExecute := seal.io.x
        bus.busy := False
      }
    }
  }
}
