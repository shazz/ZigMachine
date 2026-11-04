package zm

// VexRiscv's MulPlugin (third_party/VexRiscv, pinned: not edited) with ZM-X's
// zm.mulsh as one more leg of its writeback mux (fpga/review/KESTREL_NEXT_ISA.md 1.2):
//
//   funct7 0000001, funct3 000: rd = bits [47:16] of sext(rs1) * sext(rs2)  (Q16.16)
//                   funct3 001: rd = bits [46:15]                           (Q15)
//
// The product is MULH's: the same four 16x16 partial products in the same DSPs
// (0 DSP more), signed x signed, summed in MEMORY and WRITEBACK as MUL/MULH are, so
// the latency is MUL's. Only the writeback select differs. Used instead of MulPlugin
// when GenZm runs with --zmx; without it the netlist keeps MulPlugin itself.
//
// `mulMem` (GenZm --mulMem, vexgen flag `mulm`; review/BARD_CPI_STUDY.md): MUL (funct3 000, the low
// word) is written from MEMORY, where MUL_LOW is already summed, and bypassed from there, so an
// instruction using a MUL result waits one cycle less. MULH* and mulsh still finish in WRITEBACK.
// `zmx = false` drops mulsh's decode: the plain MulPlugin ISA.

import spinal.core._
import spinal.lib.KeepAttribute
import vexriscv._
import vexriscv.plugin._

class ZmMulPlugin(zmx: Boolean = true, mulMem: Boolean = false) extends Plugin[VexRiscv] {
  object MUL_LL extends Stageable(UInt(32 bits))
  object MUL_LH extends Stageable(SInt(34 bits))
  object MUL_HL extends Stageable(SInt(34 bits))
  object MUL_HH extends Stageable(SInt(34 bits))
  object MUL_LOW extends Stageable(SInt(34 + 16 + 2 bits))
  object IS_MUL extends Stageable(Bool)
  object IS_MULSH extends Stageable(Bool)

  override def setup(pipeline: VexRiscv): Unit = {
    import Riscv._
    import pipeline.config._
    val actions = List[(Stageable[_ <: BaseType], Any)](
      REGFILE_WRITE_VALID -> True,
      BYPASSABLE_EXECUTE_STAGE -> False,
      BYPASSABLE_MEMORY_STAGE -> False,
      RS1_USE -> True,
      RS2_USE -> True,
      IS_MUL -> True
    )
    val d = pipeline.service(classOf[DecoderService])
    d.addDefault(IS_MUL, False)
    d.addDefault(IS_MULSH, False)
    val early = actions.map { case (k, v) => if (k == BYPASSABLE_MEMORY_STAGE) (k, True) else (k, v) }
    val muls = // MUL alone when it is bypassed from MEMORY, MULH/MULHSU/MULHU as MulPlugin's MULX
      if (!mulMem) List(MULX -> actions)
      else List(M"0000001----------000-----0110011" -> early, M"0000001----------001-----0110011" -> actions,
        M"0000001----------01------0110011" -> actions)
    val mulsh = if (zmx) List(M"0000001----------00------0001011" -> (actions :+ (IS_MULSH -> True))) else Nil
    d.add(muls ++ mulsh)
  }

  override def build(pipeline: VexRiscv): Unit = {
    import pipeline._
    import pipeline.config._

    execute plug new Area {
      import execute._
      val a = input(RS1)
      val b = input(RS2)
      val signedA, signedB = Bool()
      switch(input(INSTRUCTION)(13 downto 12)) { // MULH 01: s x s, MULHSU 10: s x u
        is(B"01") { signedA := True; signedB := True }
        is(B"10") { signedA := True; signedB := False }
        default { signedA := False; signedB := False }
      }
      when(input(IS_MULSH)) { signedA := True; signedB := True }
      val aULow = a(15 downto 0).asUInt
      val bULow = b(15 downto 0).asUInt
      val aSLow = (False ## a(15 downto 0)).asSInt
      val bSLow = (False ## b(15 downto 0)).asSInt
      val aHigh = ((signedA && a.msb) ## a(31 downto 16)).asSInt
      val bHigh = ((signedB && b.msb) ## b(31 downto 16)).asSInt
      insert(MUL_LL) := aULow * bULow
      insert(MUL_LH) := aSLow * bHigh
      insert(MUL_HL) := aHigh * bSLow
      insert(MUL_HH) := aHigh * bHigh
      Component.current.afterElaboration { KeepAttribute(input(RS1)); KeepAttribute(input(RS2)) }
    }

    memory plug new Area {
      import memory._
      insert(MUL_LOW) := S(0, MUL_HL.dataType.getWidth + 16 + 2 bit) + (False ## input(MUL_LL)).asSInt +
        (input(MUL_LH) << 16) + (input(MUL_HL) << 16)
      if (mulMem) when(arbitration.isValid && input(IS_MUL) && !input(IS_MULSH) && input(INSTRUCTION)(13 downto 12) === 0) {
        output(REGFILE_WRITE_DATA) := output(MUL_LOW)(31 downto 0).asBits
      }
    }

    writeBack plug new Area {
      import writeBack._
      val result = input(MUL_LOW) + (input(MUL_HH) << 32)
      when(arbitration.isValid && input(IS_MUL)) {
        when(input(IS_MULSH)) {
          output(REGFILE_WRITE_DATA) := Mux(input(INSTRUCTION)(12), result(46 downto 15), result(47 downto 16)).asBits
        } elsewhen (input(INSTRUCTION)(13 downto 12) === 0) {
          output(REGFILE_WRITE_DATA) := input(MUL_LOW)(31 downto 0).asBits
        } otherwise {
          output(REGFILE_WRITE_DATA) := result(63 downto 32).asBits
        }
      }
    }
  }
}
