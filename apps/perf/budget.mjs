// The frame budget: what the cart may spend once FRESCO has had its share.
//
// On the board the sequencer (fpga/cycles/vseq.c) runs AFTER cart.frame() and the CPU waits
// for it, so a frame costs the cart's cycles PLUS the compositor's, end to end. The board's
// own probe says so: cart_c + comp_busy + the HBL handlers' cycles puts 101 of the 103 carts
// of the 2026-10-20 table on the right side of 60 fps (fpga/review/reports/frame_budget_2026-10-23.md).
//
// FRESCO's share is counted in LINE PASSES, the way vseq.c issues them:
//   - every enabled plane is one layer of ZM_RASTER_HEIGHT (280) passes, whatever its mode:
//     the layer walks every raster line, its handler only on the lines it covers;
//   - the clear is ONE command when there is no global (border) handler, else a BG pass a
//     line (280) with the handler between them;
//   - the dirty-line planner (vdirty.c, vadapt) may skip lines; it is NOT modelled, so these
//     are the passes a frame costs when every line is new (an upper bound).
// Each pass costs the compositor a fitted number of sys cycles (cost_model.mjs COMP_*): by the
// plane's row width and by whether its layer is the frame's first.
import { COMP_BASE, COMP_PASS, COMP_BG_PASS, FRAME_MC } from "./cost_model.mjs";
import { REG_GLOBAL_HBL_ID, REG_FB_HBL_ID, REG_FB_MODE } from "./run_cart.mjs";

const LINES = 280; // ZM_RASTER_HEIGHT
const MODES = ["normal", "fullscreen", "scroll", "medium", "overscan"];
const WIDE = new Set(["fullscreen", "medium", "overscan"]); // 400-pixel rows (machine/sdk/memmap.zig STRIDE_FULLSCREEN)

export class Budget {
    constructor(run) {
        this.run = run;
        this.frames = 0;
        this.bgPasses = 0;
        this.passes = [0, 0, 0, 0];
        this.handler = [false, false, false, false];
        this.mode = ["", "", "", ""];
        this.first = [0, 0, 0, 0]; // frames plane p was the first layer
    }

    // After the host frame: which layers the sequencer would issue for it.
    frame(acc) {
        if (!acc) return;
        const { machine, demo, memory } = this.run, base = machine.hwVideoBase(), v = new DataView(memory.buffer);
        this.frames++;
        if (v.getUint16(base + REG_GLOBAL_HBL_ID, true)) this.bgPasses += LINES;
        let first = true;
        for (let p = 0; p < Math.min(4, machine.hwPlanesNumber()); p++) {
            if (!demo.isPlaneEnabled(p)) continue;
            this.passes[p] += LINES;
            if (first) this.first[p]++, first = false;
            this.handler[p] ||= v.getUint16(base + REG_FB_HBL_ID + 2 * p, true) !== 0;
            this.mode[p] = MODES[v.getUint8(base + REG_FB_MODE + p)] ?? "?";
        }
    }

    // cartCycles: the cart's own per-frame estimate (cart, ROM, I$, CHISEL wait, HBL handlers).
    // hbl0/hbl1: run.hw.hblBy at the window's start and end.
    summary(cartCycles, hbl0, hbl1) {
        const F = Math.max(1, this.frames), Mc = (c) => Math.round(c / 1e4) / 100;
        // features: passes by kind, the quantities COMP_* multiply (apps/perf/budget_fit.mjs fits them)
        const features = { narrowFirst: 0, narrowLater: 0, wideFirst: 0, wideLater: 0, bg: this.bgPasses / F };
        const planes = this.passes.map((n, p) => {
            const kind = WIDE.has(this.mode[p]) ? "wide" : "narrow", firstShare = n ? (this.first[p] * LINES) / n : 0;
            const passes = n / F, cyc = passes * (firstShare * COMP_PASS[kind][0] + (1 - firstShare) * COMP_PASS[kind][1]);
            features[`${kind}First`] += passes * firstShare;
            features[`${kind}Later`] += passes * (1 - firstShare);
            return { p, passes: Math.round(passes), mode: this.mode[p], handler: this.handler[p], cyc,
                hblCalls: Math.round((hbl1[p] - hbl0[p]) / F) };
        }).filter((x) => x.passes > 0).map(({ cyc, ...x }) => ({ ...x, mc: Mc(cyc) }));
        const bgPasses = Math.round(features.bg);
        const comp = COMP_BASE + planes.reduce((a, x) => a + x.mc * 1e6, 0) + features.bg * COMP_BG_PASS;
        const total = cartCycles + comp, frame = FRAME_MC * 1e6;
        return {
            cartMc: Mc(cartCycles), compMc: Mc(comp), totalMc: Mc(total), allowedMc: Mc(Math.max(0, frame - comp)),
            planes, bg: { passes: bgPasses, mc: Mc(bgPasses * COMP_BG_PASS), hblCalls: Math.round((hbl1[4] - hbl0[4]) / F) },
            fps: Math.min(60, Math.round((10 * 60 * frame) / total) / 10),
            features,
            costliest: planes.length ? [...planes].sort((a, b) => b.mc - a.mc || b.hblCalls - a.hblCalls)[0].p : null,
        };
    }
}

export function printBudget(r, out = console.log) {
    const b = r.frameBudget, n = b.planes.length;
    out(`${r.tag}: cart ${b.cartMc} Mc of ${b.allowedMc} allowed with ${n} plane${n === 1 ? "" : "s"} -> ~${b.fps} fps `
        + `(cart ${b.cartMc} + FRESCO ${b.compMc} = ${b.totalMc} Mc of a ${FRAME_MC.toFixed(2)} Mc frame; ESTIMATE)`);
    for (const x of b.planes)
        out(`  plane ${x.p} ${x.mode.padEnd(10)} ${String(x.passes).padStart(4)} passes  ${String(x.mc).padStart(5)} Mc`
            + `  ${x.handler ? `HBL handler, ${x.hblCalls} calls` : "no handler"}${x.p === b.costliest && n > 1 ? "  <- costliest" : ""}`);
    if (b.bg.passes) out(`  background   ${String(b.bg.passes).padStart(4)} passes  ${String(b.bg.mc).padStart(5)} Mc  global handler, ${b.bg.hblCalls} calls (no handler: one CLEAR)`);
    out(`  passes are every line new: the board's dirty-line planner can skip unchanged ones`);
}
