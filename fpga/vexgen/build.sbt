// Custom VexRiscv netlists for the cycles sim (CYCLES.md "Memory path"): the
// `standard` core LiteX ships, with the cache geometry as parameters.
// Built against the pinned submodule third_party/VexRiscv; run through vexgen/gen.sh.
val spinalVersion = "1.13.0"

lazy val vexRiscv = RootProject(file("../third_party/VexRiscv"))

lazy val root = (project in file("."))
  .settings(
    scalaVersion := "2.12.18",
    name := "zm-vexgen",
    libraryDependencies += compilerPlugin("com.github.spinalhdl" %% "spinalhdl-idsl-plugin" % spinalVersion),
    fork := true
  )
  .dependsOn(vexRiscv)
