// Bulk word copies between the cart's DDR window and ordinary memory (ASTROLABE's staging,
// astro_stage.zig; docs/hardware/studies/ARM_FPU_COPROC.md section 4).
//
// The window is DDR inside the kernel's memory map but outside its System RAM, so ARM Linux
// maps it write-combine (Normal non-cacheable) with O_SYNC and CACHED without (phys_mem_access_prot);
// cached is not coherent with ZIGGY's HP port and ARMv7 user space cannot invalidate, so the
// window stays O_SYNC (devmem.zig). There, each LDR is a full round trip to the DDR controller
// (~160 ns, `glass astro-bench` ddr_seq); a VLDM of eight d-registers is ONE 64-byte burst,
// ~27 ns a word (ddr_vldm). Only the DDR window takes bursts: the GP0 register block (the
// mailbox) is single-beat (rtl/glass/zm_glass_regs.v), never copy it with these.
const std = @import("std");
const builtin = @import("builtin");

/// Words a burst moves: VLDM/VSTM d0-d7.
pub const BURST: usize = 16;
const is_arm = builtin.cpu.arch == .arm and std.Target.arm.featureSetHas(builtin.cpu.features, .vfp3d16);

/// `n` words from the window to ordinary memory. Both 4-aligned (Span addresses are).
pub fn load(dst: [*]u32, src: [*]const volatile u32, n: usize) void {
    var i: usize = 0;
    if (is_arm) while (i + BURST <= n) : (i += BURST) {
        asm volatile ("vldm %[s], {d0-d7}\n\tvstm %[d], {d0-d7}"
            :
            : [s] "r" (src + i),
              [d] "r" (dst + i),
            : .{ .d0 = true, .d1 = true, .d2 = true, .d3 = true, .d4 = true, .d5 = true, .d6 = true, .d7 = true, .memory = true });
    };
    while (i < n) : (i += 1) dst[i] = src[i];
}

/// `n` words from ordinary memory to the window.
pub fn store(dst: [*]volatile u32, src: [*]const u32, n: usize) void {
    var i: usize = 0;
    if (is_arm) while (i + BURST <= n) : (i += BURST) {
        asm volatile ("vldm %[s], {d0-d7}\n\tvstm %[d], {d0-d7}"
            :
            : [s] "r" (src + i),
              [d] "r" (dst + i),
            : .{ .d0 = true, .d1 = true, .d2 = true, .d3 = true, .d4 = true, .d5 = true, .d6 = true, .d7 = true, .memory = true });
    };
    while (i < n) : (i += 1) dst[i] = src[i];
}
