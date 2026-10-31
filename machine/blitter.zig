// --------------------------------------------------------------------------
// ZigMachine — SEALED blitter (the 2D drawing coprocessor, CHISEL on KESTREL).
//
// Lives inside machine-video.wasm, sharing the video hardware region with the
// framebuffers it draws into. ZigOS sets the blitter register block (memmap
// BLIT_*) then calls the sealed `hwBlit()` export, which runs execute() here.
//
// Synchronous: FILL, BLIT (3-source minterm / colour-key cookie-cut), LINE
// (Bresenham), TRIANGLE (deterministic odd-even scanline fill), in
// blitter_ops.zig. It writes the logical framebuffers as chunky 8bpp palette
// indices; the video machine composites them as usual.
//
// Coders never see this source. See docs/BLITTER_HW_SPEC.md for the model; the
// RTL (fpga/rtl/blitter) is proven equal to this file (fpga/tests/test_rtl_blitter.py).
// --------------------------------------------------------------------------
const memmap = @import("sdk/memmap.zig");
const regs = @import("blitter_regs.zig");
const check = @import("blitter_check.zig");
const ops = @import("blitter_ops.zig");

// --------------------------------------------------------------------------
// Entry point (wrapped as hwBlit() in machine_video.zig)
// --------------------------------------------------------------------------
pub fn execute() void {
    const cmd = regs.r8(memmap.BLIT_COMMAND);
    if (cmd == memmap.BLIT_CMD_NOP) return;
    regs.w8(memmap.BLIT_STATUS, memmap.BLIT_STATUS_BUSY);

    const con = regs.r8(memmap.BLIT_CON);
    const con2 = regs.r8(memmap.BLIT_CON2);
    const d_base: usize = regs.r32(memmap.BLIT_D_BASE);
    const d_stride = regs.r16(memmap.BLIT_D_STRIDE);
    const clip = regs.clipRect(con, d_stride);
    var cost: u32 = 0;

    // D never leaves the video region: before 1.4.0 a bad D_BASE could scribble
    // the ROM's RAM (it sits 2 MiB above the base) or trap past the end of memory.
    const box = check.opBox(cmd, clip);
    if (!check.destInRegion(regs.r32(memmap.BLIT_D_BASE), d_stride, box.x0, box.y0, box.x1, box.y1)) {
        regs.w32(memmap.BLIT_CYCLES, 0);
        regs.w8(memmap.BLIT_STATUS, 0);
        return;
    }
    const d: [*]u8 = @ptrFromInt(memmap.HW_VIDEO_BASE + d_base);

    switch (cmd) {
        memmap.BLIT_CMD_FILL => ops.doFill(d, d_stride, clip, con2, &cost),
        memmap.BLIT_CMD_BLIT => ops.doBlit(d, d_stride, clip, con, &cost),
        memmap.BLIT_CMD_LINE => ops.doLine(d, d_stride, clip, &cost),
        memmap.BLIT_CMD_TRIANGLE => ops.doTriangle(d, d_stride, clip, con2, &cost),
        else => {},
    }

    regs.w32(memmap.BLIT_CYCLES, cost);
    regs.w8(memmap.BLIT_STATUS, 0);
}
