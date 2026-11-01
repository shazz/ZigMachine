package zm

// ZM-X v1, the one-cycle half (fpga/review/KESTREL_NEXT_ISA.md 1.2-1.3): R-type ops
// on custom-0 (opcode 0x0B). The integer semantics are the spec the software twins
// implement (libs/zig/zmx.zig, fpga/cycles/zmx_twin.h); tests/test_zmx.py runs every
// op on the core against them. zm.mulsh is the other half (ZmMulPlugin: MulPlugin's DSPs).
//
//   funct7      funct3  op         rd
//   0000010     k 1..3  funnel     (rs1 >> 8k) | (rs2 << (32 - 8k))
//   0000011     000     add8s      per unsigned byte lane: min(a + b, 255)
//   0000100     000     sub8s      per lane: max(a - b, 0)
//   0000101     000     avg8       per lane: (a + b) >> 1 (floor)
//   0000110     000     add8       per lane: (a + b) & 255
//   0hhhwww     111     tex2d      (((rs2 >> 16) & (H-1)) << logW) | ((rs1 >> 16) & (W-1)),
//                                  logW = www + 3, logH = hhh + 3 (8..1024)
// Every other custom-0 encoding stays illegal (DecoderSimplePlugin traps it).
//
// `early` = false (the default) writes the result from MEMORY, not EXECUTE: the ops'
// adders and the funnel/tex2d muxes sit behind a pipeline register instead of in front
// of the execute-stage result mux and its bypass, which is the core's critical cone
// (CYCLES.md "Branch prediction and the clock"). A dependent instruction right behind
// one waits a cycle; a loop that interleaves (the fire row: two loads between the ops)
// pays nothing. `early` = true is the note's 1-cycle-bypass form, kept to measure.

import spinal.core._
import vexriscv._
import vexriscv.plugin._

class ZmXPlugin(early: Boolean = false) extends Plugin[VexRiscv] {
  object IS_ZMX extends Stageable(Bool)
  object ZMX_RESULT extends Stageable(Bits(32 bits))

  override def setup(pipeline: VexRiscv): Unit = {
    import pipeline.config._
    val actions = List[(Stageable[_ <: BaseType], Any)](
      IS_ZMX -> True,
      REGFILE_WRITE_VALID -> True,
      BYPASSABLE_EXECUTE_STAGE -> Bool(early),
      BYPASSABLE_MEMORY_STAGE -> True,
      RS1_USE -> True,
      RS2_USE -> True
    )
    val d = pipeline.service(classOf[DecoderService])
    d.addDefault(IS_ZMX, False)
    val keys = List(
      M"0000010----------001-----0001011", // funnel 1
      M"0000010----------010-----0001011", // funnel 2
      M"0000010----------011-----0001011", // funnel 3
      M"0000011----------000-----0001011", // add8s
      M"0000100----------000-----0001011", // sub8s
      M"0000101----------000-----0001011", // avg8
      M"0000110----------000-----0001011", // add8
      M"0----------------111-----0001011" // tex2d
    )
    d.add(keys.map(_ -> actions))
  }

  override def build(pipeline: VexRiscv): Unit = {
    import pipeline._
    import pipeline.config._

    execute plug new Area {
      import execute._
      val a = input(RS1).asUInt
      val b = input(RS2).asUInt
      val ins = input(INSTRUCTION)
      val f3 = ins(14 downto 12)
      val f7 = ins(31 downto 25)
      insert(ZMX_RESULT) := ZmXAlu.result(a, b, f3, f7)
      if (early) when(input(IS_ZMX)) { output(REGFILE_WRITE_DATA) := input(ZMX_RESULT) }
    }

    if (!early) memory plug new Area {
      import memory._
      when(arbitration.isValid && input(IS_ZMX)) { output(REGFILE_WRITE_DATA) := input(ZMX_RESULT) }
    }
  }
}

object ZmXAlu {
  def lanes(a: UInt, b: UInt)(f: (UInt, UInt) => Bits): Bits =
    msbFirst(i => f(a(8 * i + 7 downto 8 * i), b(8 * i + 7 downto 8 * i)))

  // lane 3 in the top bits, lane 0 in the bottom: little-endian bytes, as the twins see them
  def msbFirst(f: Int => Bits): Bits = (3 to 0 by -1).map(f).reduce(_ ## _)

  def tex2d(a: UInt, b: UInt, f7: Bits): Bits = {
    val logW = f7(2 downto 0).asUInt.resize(5) + 3
    val logH = f7(5 downto 3).asUInt.resize(5) + 3
    val mask = (w: UInt) => (U(1, 11 bits) |<< w) - 1 // 2^w - 1, w in 3..10
    val u = a(25 downto 16) & mask(logW)(9 downto 0)
    val v = b(25 downto 16) & mask(logH)(9 downto 0)
    (v.resize(20) |<< logW | u.resize(20)).resize(32).asBits
  }

  def result(a: UInt, b: UInt, f3: Bits, f7: Bits): Bits = {
    val r = Bits(32 bits)
    val sum = lanes(a, b)((x, y) => (x +^ y).asBits) // 9 bits a lane, carry on top
    def sumLane(i: Int) = sum(9 * i + 8 downto 9 * i)
    val add8s = msbFirst(i => Mux(sumLane(i)(8), B"8'xFF", sumLane(i)(7 downto 0)))
    val add8 = msbFirst(i => sumLane(i)(7 downto 0))
    val avg8 = msbFirst(i => sumLane(i)(8 downto 1))
    val sub8s = lanes(a, b)((x, y) => Mux(x < y, B"8'x00", (x - y).asBits))
    val funnel = f3(1 downto 0).mux(
      1 -> (b(7 downto 0) ## a(31 downto 8)),
      2 -> (b(15 downto 0) ## a(31 downto 16)),
      default -> (b(23 downto 0) ## a(31 downto 24))
    )
    r := funnel
    when(f3 === 7) { r := tex2d(a, b, f7) }
      .elsewhen(f7(2 downto 0) === 3) { r := add8s }
      .elsewhen(f7(2 downto 0) === 4) { r := sub8s }
      .elsewhen(f7(2 downto 0) === 5) { r := avg8 }
      .elsewhen(f7(2 downto 0) === 6) { r := add8 }
    r
  }
}
