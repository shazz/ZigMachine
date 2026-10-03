package zm

// LiteX's VexRiscv `standard` (pythondata-cpu-vexriscv GenCoreDefault with its
// defaults: rv32im, single-cycle mul/div, static prediction, small CSRs, 32-byte
// lines, Wishbone buses) with the I$/D$ size and way count as parameters. Only
// the plugins `standard` uses are kept, so with the defaults the netlist is the
// same core as LiteX's VexRiscv.v, regenerated from third_party/VexRiscv.
//
//   sbt "runMain zm.GenZm --iCacheSize 16384 --iWays 2 --outputFile VexRiscv_I16w2"

import spinal.core._
import spinal.core.internals.{PhaseAllocateNames, PhaseContext}
import vexriscv._
import vexriscv.ip.{DataCacheConfig, InstructionCacheConfig}
import vexriscv.plugin.CsrAccess.WRITE_ONLY
import vexriscv.plugin._

case class ZmArgs(
    iCacheSize: Int = 4096,
    iWays: Int = 1,
    dCacheSize: Int = 4096,
    dWays: Int = 1,
    seal: Boolean = false,
    relaxedPc: Boolean = false,
    prediction: String = "STATIC", // NONE | STATIC | DYNAMIC_TARGET (fpga/README.md "Timing under openXC7")
    outputFile: String = "VexRiscv",
    targetDirectory: String = "."
)

object GenZm {
  def parse(args: Array[String]): ZmArgs = {
    val p = new scopt.OptionParser[ZmArgs]("GenZm") {
      opt[Int]("iCacheSize").action((v, c) => c.copy(iCacheSize = v))
      opt[Int]("iWays").action((v, c) => c.copy(iWays = v))
      opt[Int]("dCacheSize").action((v, c) => c.copy(dCacheSize = v))
      opt[Int]("dWays").action((v, c) => c.copy(dWays = v))
      opt[Unit]("seal").action((_, c) => c.copy(seal = true))
      opt[Unit]("relaxedPc").action((_, c) => c.copy(relaxedPc = true))
      opt[String]("prediction").action((v, c) => c.copy(prediction = v))
      opt[String]("outputFile").action((v, c) => c.copy(outputFile = v))
      opt[String]("targetDirectory").action((v, c) => c.copy(targetDirectory = v))
    }
    p.parse(args, ZmArgs()).get
  }

  // NONE: no prediction at all, a taken branch costs the flush. It removes the
  // decode-stage I$-word -> static target -> fetch PC cone (fpga/TIMING_FABLE.md),
  // for +8 % sys fmax over a seed sweep and +16-25 % cycles (fpga/CYCLES.md).
  def branchPrediction(name: String): BranchPrediction = name match {
    case "NONE" => NONE
    case "STATIC" => STATIC
    case "DYNAMIC_TARGET" => DYNAMIC_TARGET
    case other => throw new IllegalArgumentException(s"--prediction $other: NONE, STATIC or DYNAMIC_TARGET")
  }

  def iBus(a: ZmArgs) = new IBusCachedPlugin(
    resetVector = null,
    relaxedPcCalculation = a.relaxedPc, // fmax: a register between the PC and the I$ (one more fetch stage)
    prediction = branchPrediction(a.prediction),
    compressedGen = false,
    memoryTranslatorPortConfig = null,
    config = InstructionCacheConfig(
      cacheSize = a.iCacheSize, bytePerLine = 32, wayCount = a.iWays, addressWidth = 32,
      cpuDataWidth = 32, memDataWidth = 32, catchIllegalAccess = true, catchAccessFault = true,
      asyncTagMemory = false, twoCycleRam = false, twoCycleCache = true
    )
  )

  def dBus(a: ZmArgs) = new DBusCachedPlugin(
    dBusCmdMasterPipe = true,
    dBusCmdSlavePipe = true,
    dBusRspSlavePipe = false,
    relaxedMemoryTranslationRegister = false,
    config = new DataCacheConfig(
      cacheSize = a.dCacheSize, bytePerLine = 32, wayCount = a.dWays, addressWidth = 32,
      cpuDataWidth = 32, memDataWidth = 32, catchAccessError = true, catchIllegal = true,
      catchUnaligned = true, withLrSc = false, withAmo = false, earlyWaysHits = true
    ),
    memoryTranslatorPortConfig = null,
    csrInfo = true
  )

  // --seal (rtl/seal/README.md): U-mode, illegal CSR/xRET from U trapped,
  // mscratch for the trap handler's stack swap, and the window translator.
  def csr(a: ZmArgs) = {
    val small = CsrPluginConfig.small(mtvecInit = null).copy(mtvecAccess = WRITE_ONLY, ecallGen = true, wfiGenAsNop = true)
    if (a.seal) small.copy(userGen = true, catchIllegalAccess = true, mscratchGen = true) else small
  }

  def translator(a: ZmArgs): Plugin[VexRiscv] =
    if (a.seal) new ZmSealPlugin(ioRange = _.msb) else new StaticMemoryTranslatorPlugin(ioRange = _.msb)

  def pipeline(a: ZmArgs): List[Plugin[VexRiscv]] = List(
    translator(a),
    new DecoderSimplePlugin(catchIllegalInstruction = true),
    new RegFilePlugin(regFileReadyKind = plugin.SYNC, zeroBoot = false),
    new IntAluPlugin,
    new SrcPlugin(separatedAddSub = false, executeInsertion = true),
    new FullBarrelShifterPlugin,
    new HazardSimplePlugin(
      bypassExecute = true, bypassMemory = true, bypassWriteBack = true, bypassWriteBackBuffer = true,
      pessimisticUseSrc = false, pessimisticWriteRegFile = false, pessimisticAddressMatch = false
    ),
    new BranchPlugin(earlyBranch = false, catchAddressMisaligned = true),
    new CsrPlugin(csr(a)),
    new MulPlugin,
    new DivPlugin,
    new ExternalInterruptArrayPlugin(
      machineMaskCsrId = 0xbc0, machinePendingsCsrId = 0xfc0,
      supervisorMaskCsrId = 0x9c0, supervisorPendingsCsrId = 0xdc0
    )
  )

  def main(args: Array[String]): Unit = {
    val a = parse(args)
    val config = SpinalConfig(
      defaultConfigForClockDomains = ClockDomainConfig(resetKind = spinal.core.SYNC),
      netlistFileName = a.outputFile + ".v",
      targetDirectory = a.targetDirectory
    )
    config.phasesInserters += { array =>
      array.insert(array.indexWhere(_.isInstanceOf[PhaseAllocateNames]) + 1, new ForceRamBlockPhase)
    }
    config.generateVerilog {
      val cpuConfig = VexRiscvConfig(iBus(a) :: dBus(a) :: pipeline(a))
      val cpu = new VexRiscv(cpuConfig)
      cpu.rework {
        for (p <- cpuConfig.plugins) p match {
          case p: IBusCachedPlugin =>
            p.iBus.setAsDirectionLess()
            spinal.lib.master(p.iBus.toWishbone()).setName("iBusWishbone")
          case p: DBusCachedPlugin =>
            p.dBus.setAsDirectionLess()
            spinal.lib.master(p.dBus.toWishbone()).setName("dBusWishbone")
          case _ =>
        }
      }
      cpu
    }
  }
}

// As GenCoreDefault: (* ram_style = "block" *) on every synchronous RAM.
class ForceRamBlockPhase extends spinal.core.internals.Phase {
  override def impl(pc: PhaseContext): Unit = pc.walkBaseNodes {
    case mem: Mem[_] =>
      var asyncRead = false
      mem.dlcForeach[MemPortStatement] {
        case _: MemReadAsync => asyncRead = true
        case _ =>
      }
      if (!asyncRead) mem.addAttribute("ram_style", "block")
    case _ =>
  }
  override def hasNetlistImpact: Boolean = false
}
