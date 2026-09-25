// --------------------------------------------------------------------------
// Every routine address the sequencer or the main loop calls, to its part's
// function (rip.Hook names them part_method, as model.py does), plus the
// three system hooks: colour 0 black / white, and the music (music.zig).
// --------------------------------------------------------------------------
const core = @import("core.zig");
const rip = @import("rip.zig");
const music = @import("music.zig");
const p1 = @import("p1.zig");
const p2 = @import("p2.zig");
const p3 = @import("p3.zig");
const tr = @import("tr.zig");
const p5 = @import("p5.zig");
const p6 = @import("p6.zig");
const p7 = @import("p7.zig");
const p8 = @import("p8.zig");
const p9 = @import("p9.zig");
const p10 = @import("p10.zig");
const p11 = @import("p11.zig");
const p12 = @import("p12.zig");
const p13 = @import("p13.zig");
const p14 = @import("p14.zig");
const p15 = @import("p15.zig");
const p16 = @import("p16.zig");
const p17 = @import("p17.zig");

pub fn reset() void {
    inline for (.{ p1, p2, p3, tr, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15, p16, p17 }) |p| p.reset();
    music.reset();
}

pub fn call(h: rip.Hook, frame: u32) void {
    switch (h) {
        .nop, .tune2_load => {},
        .pal_black => core.colour = 0,
        .pal_white => core.colour = 0x777,
        .music_on => music.on(frame),
        .music_off => music.off(),
        .p1_init => p1.init(),
        .p1_vbl => p1.vbl(),
        .p1_reveal => p1.reveal(),
        .p1_lines_up => p1.linesUp(),
        .p1_lines_seq => p1.linesSeq(),
        .p1_pal_down => p1.palDown(),
        .p1_white_out => p1.whiteOut(),
        .p2_init => p2.init(),
        .p2_vbl => p2.vbl(),
        .p2_bars => p2.bars(),
        .p2_m10e7a => p2.m10e7a(),
        .p2_m10eba => p2.m10eba(),
        .p2_m10eda => p2.m10eda(),
        .p2_m10efe => p2.m10efe(),
        .p2_m10f34 => p2.m10f34(),
        .p2_m1108c => p2.m1108c(),
        .p2_m110e8 => p2.m110e8(),
        .p2_m11102 => p2.m11102(),
        .p3_init => p3.init(),
        .p3_v1ad1a => p3.v1ad1a(),
        .p3_v1ad24 => p3.v1ad24(),
        .p3_v1ad10 => p3.v1ad10(),
        .p3_v1acee => p3.v1acee(),
        .p3_v1ad42 => p3.v1ad42(),
        .p3_m1ad5e => p3.m1ad5e(),
        .tr_i21842 => tr.init(0),
        .tr_i21866 => tr.init(1),
        .tr_i2188a => tr.init(2),
        .tr_i218ae => tr.init(3),
        .tr_vbl => tr.vbl(),
        .tr_roll_in => tr.rollIn(),
        .tr_roll_out => tr.rollOut(),
        .p5_init => {}, // the 128-frame precalc: computed per row here (p5.zig)
        .p5_vbl => p5.vbl(),
        .p5_m1a1c2 => p5.m1a1c2(),
        .p5_m1a22a => p5.m1a22a(),
        .p5_m1a216 => p5.m1a216(),
        .p6_init => p6.init(),
        .p6_vbl => p6.vbl(),
        .p6_post_up => p6.postUp(),
        .p6_post_down => p6.postDown(),
        .p6_render => p6.render(),
        .p7_init => p7.init(),
        .p7_vbl => p7.vbl(),
        .p7_m18748 => p7.m18748(),
        .p7_m18756 => p7.m18756(),
        .p7_m187a4 => p7.m187a4(),
        .p8_init => p8.init(),
        .p8_vbl => p8.vbl(),
        .p9_init => p9.init(),
        .p9_vbl => p9.vbl(),
        .p9_m12e8a => p9.m12e8a(),
        .p9_m12eb8 => p9.m12eb8(),
        .p9_m12e76 => p9.m12e76(),
        .p9_p0 => p9.image(0),
        .p9_p1 => p9.image(1),
        .p9_p2 => p9.image(2),
        .p9_p3 => p9.image(3),
        .p9_p4 => p9.image(4),
        .p10_init => p10.init(),
        .p10_vbl => p10.vbl(),
        .p11_init => p11.init(),
        .p11_vbl => p11.vbl(),
        .p11_m1bac2 => p11.m1bac2(),
        .p11_m1bb22 => p11.m1bb22(),
        .p11_m1bb28 => p11.m1bb28(),
        .p11_m1bb32 => p11.m1bb32(),
        .p11_m1bae6 => p11.m1bae6(),
        .p12_init => p12.init(),
        .p12_vbl_in => p12.vblIn(),
        .p12_vbl => p12.vbl(),
        .p12_vbl_out => p12.vblOut(),
        .p12_step => p12.step(),
        .p13_init => p13.init(),
        .p13_vbl => p13.vbl(),
        .p13_m1c6b8 => p13.m1c6b8(),
        .p13_dec => p13.dec(),
        .p13_mA => p13.mode(0),
        .p13_mB => p13.mode(1),
        .p13_mC => p13.mode(2),
        .p13_s1 => p13.strip(0),
        .p13_s2 => p13.strip(1),
        .p13_s3 => p13.strip(2),
        .p14_init => p14.init(),
        .p14_vbl => p14.vbl(),
        .p14_frame => p14.frame(),
        .p14_m1a80a => p14.m1a80a(),
        .p14_m1a822 => p14.m1a822(),
        .p15_init => p15.init(),
        .p15_vbl => p15.vbl(),
        .p15_frame => p15.frame(),
        .p15_p1 => p15.p1(),
        .p15_p2 => p15.p2(),
        .p15_p3 => p15.p3(),
        .p16_init => p16.init(),
        .p16_vbl => p16.vbl(),
        .p16_post92 => p16.post92(),
        .p16_post93 => p16.post93(),
        .p16_post94 => p16.post94(),
        .p16_m92 => p16.m92(),
        .p16_m93 => p16.m93(),
        .p16_m95 => p16.m95(),
        .p17_init => p17.init(),
        .p17_vbl => p17.vbl(),
        .p17_m20530 => p17.m20530(),
        .p17_pAB => p17.pAB(),
        .p17_pB => p17.pB(),
        else => unreachable, // kernels never come through here
    }
}

pub fn kernel(h: rip.Hook, l0: u32) void {
    switch (h) {
        .p1_kernel => p1.kernel(l0),
        .p2_kernel => p2.kernel(l0),
        .p3_kernel => p3.kernel(l0),
        .tr_kernel => tr.kernel(l0),
        .p5_kernel => p5.kernel(l0),
        .p6_kernel => p6.kernel(l0),
        .p7_kernel => p7.kernel(l0),
        .p8_kernel => p8.kernel(l0),
        .p9_kernel => p9.kernel(l0),
        .p10_k0 => p10.kernel(l0, 0),
        .p10_k1 => p10.kernel(l0, 1),
        .p10_k2 => p10.kernel(l0, 2),
        .p11_kernel => p11.kernel(l0),
        .p12_kernel => p12.kernel(l0),
        .p13_kernel => p13.kernel(l0),
        .p14_kernel => p14.kernel(l0),
        .p15_kernel => p15.kernel(l0),
        .p16_kernel => p16.kernel(l0),
        .p17_kernel => p17.kernel(l0),
        else => unreachable,
    }
}

pub fn finish(job: core.Job) void {
    switch (job.what) {
        .p7_rest => p7.renderRest(job.arg),
        .p7_reveal => p7.reveal(),
        .p7_m18756b => p7.m18756b(),
        .p7_m187a4b => p7.m187a4b(),
        .p9_swap => p9.swap(),
        .p16_show => p16.show(),
        .p16_m92b => p16.m92b(),
        .p16_m93b => p16.m93b(),
        .p16_m95b => p16.m95b(),
    }
}
