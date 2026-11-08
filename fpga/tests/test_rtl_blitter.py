"""The RTL blitter (rtl/blitter/zm_blit.v) against the Zig machine's own blitter.

tests/blitter_ref runs machine/blitter.zig natively, unchanged, on a script of register
writes and `run`s over a 6 MiB memory image; tests/tb/blitter_tb.cpp plays the same script
into the RTL (CXXRTL), behind ports that answer like a loaded DDR, and compares after every
op the CYCLES readback, STATUS and a hash of the whole memory window. The scripts are the
hand-written edge cases (blitter_edges.py) and randomised ops (blitter_random.py).

The break tests (ZM_RTL_BREAK=1) break one rule of the RTL at a time and require a failure.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yowasp_yosys

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tests"))
import test_rtl  # after the path insert: reuses its CXXRTL include path
from blitter_edges import edge_script
from blitter_queue import make_queue_script
from blitter_random import make_script
from blitter_speed import H, W, speed_script
from blitter_tex import make_tex_script
from blitter_tri import make_tri_script

BUILD = FPGA / "build" / "tests" / "blitter"
ZIG = os.environ.get("ZIG", str(Path.home() / ".local/zig/0.16.0/zig"))
FILES = sorted(p.name for p in (FPGA / "rtl/blitter").glob("zm_blit*"))  # the .v files and the .vh they include
RTL = [f for f in FILES if f.endswith(".v")]
SCRIPTS = {
    "edges": edge_script,
    "random1": lambda: make_script(1, 400),
    "random2": lambda: make_script(2, 400),
    "speed": lambda: speed_script()[0],
    "tex1": lambda: make_tex_script(3, 320),
    "queue1": lambda: make_queue_script(3, 40),
    "tri1": lambda: make_tri_script(5, 3000),
}
# (name, file, the text, its broken form): each rule of the blitter, broken one at a time.
MUTANTS = [
    ("minterm_index_swapped", "zm_blit_pxq.v", "mt[{h_a[i], bval[i], cen && h_c[i]}]", "mt[{cen && h_c[i], bval[i], h_a[i]}]"),
    ("clip_bottom_off_by_one", "zm_blit_clip.v", "ry < dh ? ry : dh", "ry < dh ? ry + 18'sd1 : dh"),
    ("bresenham_tie_break", "zm_blit_line.v", "mx = e2 >= dy", "mx = e2 > dy"),
    # TRIANGLE's edge walk (zm_blit_tri, _twalk, _div): the model's per-line floor divide, bit for bit
    ("triangle_bottom_edge_closed", "zm_blit_tri.v", "if (ys >= lb ||", "if (ys > lb ||"),
    # without the dy * 2^16 offset a negative slope's numerator wraps: no floor, no remainder
    ("triangle_numerator_offset_dropped", "zm_blit_tri.v", " + $signed({1'b0, sdy, 16'd0})", ""),
    ("triangle_quotient_bits_shifted", "zm_blit_tri.v", "+ q[15:0];", "+ q[16:1];"),
    ("triangle_carry_on_remainder_above_dy", "zm_blit_twalk.v", "sb && !radd[17];", "sb && !radd[17] && radd[16:0] != 17'd0;"),
    ("triangle_carry_not_added_to_x", "zm_blit_twalk.v", "(sa ? qd : 16'd0) + {15'd0, carry}", "(sa ? qd : 16'd0)"),
    ("triangle_start_offset_skipped", "zm_blit_tri.v", "t <= {6'd0, y} - ay;", "t <= 16'd0;"),
    ("triangle_short_edge_never_switches", "zm_blit_tri.v", "sid == 2'd1 && ys >= sb", "1'b0 && ys >= sb"),
    ("triangle_divide_drops_the_high_half", "zm_blit_div.v", "r <= num[32:17];", "r <= 16'd0;"),
    ("desc_ignored", "zm_blit_core.v", ".desc(f_con[6])", ".desc(1'b0)"),
    ("key_compare_inverted", "zm_blit_pxq.v", "bv_next == key", "bv_next != key"),
    # the key test made as the head loads: it must be the loading pixel's B, not the one in H
    ("word_compared_to_the_buffer_before_it_moves", "zm_blit_pxq.v", "h_weq <= (h_ret && h_wr ? h_dst[22:2] : c_word) == hd[22:2];",
     "h_weq <= c_word == hd[22:2];"),
    ("key_tested_on_the_pixel_before", "zm_blit_pxq.v", "h_skip <= skip_next;", "h_skip <= keyen && bval == key;"),
    ("halftone_bit_order", "zm_blit_regs.v", "{nz[hi] ? lane[hi[1:0]] : 8'd0, nz[lo] ? lane[lo[1:0]] : 8'd0}",
     "{nz[lo] ? lane[lo[1:0]] : 8'd0, nz[hi] ? lane[hi[1:0]] : 8'd0}"),
    ("halftone_sniff_counts_zero_bytes", "zm_blit_regs.v", "<= ld_data[8*(b%4) +: 8] != 8'd0;", "<= 1'b1;"),
    ("halftone_sniff_dropped", "zm_blit_core.v", "f_con2[2] || ht_nz", "f_con2[2]"),
    ("fill_ignores_fill_mt", "zm_blit_core.v", "is_fill && !fill_mt ? 8'hCC : f_mt", "f_mt"),
    ("fill_cost_not_wh", "zm_blit_core.v", "cost <= fill_cost;", "cost <= fill_cost + 32'd1;"),
    ("region_check_off_by_one", "zm_blit_chk.v", "+ dlast_q <= ZM_REGION_BYTES", "+ dlast_q < ZM_REGION_BYTES"),
    ("window_top_off_by_one", "zm_blit_chk.v", "hi <= ZM_ROM_RAM_TOP", "hi < ZM_ROM_RAM_TOP"),
    ("src_abs_ignored", "zm_blit_core.v", "wire abs_src = f_con2[0];", "wire abs_src = 1'b0;"),
    # the two banks and the sequencer (zm_blit_regs, zm_blit_q): no store dropped, none seen early
    ("store_dropped_while_busy", "zm_blit_regs.v", "always @(posedge clk) if (cpu_we) begin", "always @(posedge clk) if (cpu_we && !busy) begin"),
    ("op_bank_not_loaded_at_a_kick", "zm_blit_q.v", "ld_we <= 1'b1; ld_word <= idx;", "ld_word <= idx;"),
    ("queue_starts_from_the_last_op", "zm_blit_q.v", "if (idx == 5'd23) st <= is_q ? HDR : SET;", "st <= is_q ? HDR : SET;"),
    ("descriptor_of_a_blit_skipped", "zm_blit_q.v", "st <= ocmd != 8'd0 && (", "st <= ocmd > 8'd1 && ("),
    ("queued_op_below_vram_runs", "zm_blit_q.v", "(!is_q || d_base >= ZM_OFF_VRAM)", "1'b1"),
    ("two_ops_at_once", "zm_blit_q.v", "WAIT: if (!core_busy)", "WAIT: if (1'b1)"),
    ("words_highest_first", "zm_blit_q.v", "for (k = 23; k >= 0; k = k - 1)", "for (k = 0; k < 24; k = k + 1)"),
    ("idle_before_the_list_ends", "zm_blit.v", "core_busy || q_busy || kick", "core_busy || kick"),
    ("count_off_by_one", "zm_blit_q.v", "left <= kick_data[26:17];", "left <= kick_data[26:17] + 10'd1;"),
    ("list_read_past_its_count", "zm_blit_q.v", "SET : left == 10'd0 ? IDLE : WRD2;", "SET : WRD2;"),
    ("queue_cost_not_summed", "zm_blit_regs.v", "cycles <= cycles + cyc_val;", "cycles <= cyc_val;"),
    ("word0_drops_con", "zm_blit_q.v", "ld_be <= mask[0] ? 4'b0110 : 4'b1111;", "ld_be <= mask[0] ? 4'b0010 : 4'b1111;"),
    ("write_lane_wrong", "zm_blit_pxq.v", "c_strb <= 4'b0001 << h_dst[1:0];", "c_strb <= 4'b0001 << h_dst[3:2];"),
    ("halftone_declared_ignored", "zm_blit_core.v", "f_con2[2] || ht_nz", "ht_nz"),
    ("clip_right_off_by_one", "zm_blit_clip.v", "rx < sds ? rx : sds", "rx < sds ? rx + 18'sd1 : sds"),
    ("fullscreen_height_ignored", "zm_blit_clip.v", "ZM_PHYSICAL_HEIGHT : ZM_HEIGHT", "ZM_HEIGHT : ZM_HEIGHT"),
    ("triangle_span_not_clipped", "zm_blit_tri.v", "x <= xl > cx0 ? xl : cx0;", "x <= xl;"),
    ("key_skipped_pixels_counted", "zm_blit_pxq.v", "assign wrote = h_ret && !skip;", "assign wrote = h_ret;"),
    # the no-op pixel (zm_blit_px.v): an AND (or MT_B) of a 0 is not "unchanged"; a B channel is not a constant
    ("nop_pixel_ignores_the_minterm", "zm_blit_core.v", "(!m[0] && m[1])", "(!m[0])"),
    ("nop_pixel_ignores_the_channels", "zm_blit_core.v", "px_flags == 4'b0100 && id_0", "id_0"),
    ("nop_pixel_ignores_the_halftone", "zm_blit_core.v", "(pick_bg ? id_bg : id_fg)", "id_fg"),
    ("nop_pixel_not_counted", "zm_blit_pxq.v", "assign wrote = h_ret && !skip;", "assign wrote = h_ret && !skip && !h_nop;"),
    ("line_clipped_pixels_uncounted", "zm_blit_core.v", "line_step && is_line", "line_step && is_line && |v"),
    # the pipeline (zm_blit_px/_pxq): reads ahead of writes only where they cannot alias, answers
    # paired with the request that asked, merged bytes in their own word and lane
    ("read_passes_an_aliasing_write", "zm_blit_core.v", ".ordered((is_blit || is_tex) && overlap || ord_c)", ".ordered(ord_c)"),
    ("overlap_ignores_channel_a", "zm_blit_chk.v", "ord_acc || !(apart", "ord_acc || sel && !(apart"),
    ("overlap_source_is_one_row", "zm_blit_chk.v", "+ {2'b00, prod[22:0]} + {4'd0, s_w}", "+ {4'd0, s_w}"),
    # the in-plane overlap (SOC_REVIEW F5): the box's own span, and a walk that never reads behind itself
    ("dest_span_starts_at_the_last_row", "zm_blit_chk.v", "d_lin + p_first +", "d_lin + p_last +"),
    ("behind_test_ignores_the_direction", "zm_blit_chk.v", "(desc ? delta <= 27'sd0 : delta >= 27'sd0)", "1'b1"),
    ("behind_test_ignores_the_stride", "zm_blit_chk.v", "(h == 16'd1 || s_str == ds)", "1'b1"),
    ("poly_box_skips_the_third_vertex", "zm_blit_chk.v", "TRIANGLE ? y2 : y0;", "TRIANGLE ? y0 : y0;"),
    ("answer_paired_with_the_newest_read", "zm_blit_px.v", "tag[tr[LT-1:0]]", "tag[tw[LT-1:0] - 1'b1]"),
    ("answer_byte_from_the_wrong_lane", "zm_blit_pxq.v", "wa >> {h_lanes[1:0], 3'b000}", "wa >> {h_lanes[3:2], 3'b000}"),
    ("pixel_leaves_before_its_answers", "zm_blit_pxq.v", "h_got == q_need[hs]", "h_got[0] == q_need[hs][0]"),
    ("bytes_merged_across_words", "zm_blit_pxq.v", "wire same = cv && h_weq;", "wire same = cv;"),
    # word reuse: never across ops, never a source an ordered op may write, always the last word fetched
    ("reuse_survives_between_ops", "zm_blit_px.v", "if (px_idle) lw_v <= 3'd0;", ""),
    ("reuse_of_sources_while_ordered", "zm_blit_px.v", "{!ordered_c, !ordered, !ordered}", "{!ordered_c, 2'b11}"),
    ("reuse_of_c_when_a_pixel_may_come_twice", "zm_blit_px.v", "{!ordered_c, !ordered, !ordered}", "{1'b1, !ordered, !ordered}"),
    ("reuse_takes_an_older_word", "zm_blit_pxq.v", "if (h_need[2]) hw_c <= wc;", "if (h_need[2] && hw_c == 0) hw_c <= wc;"),
    ("reuse_ignores_the_word_address", "zm_blit_px.v", "lw_c == p_dst[22:2]", "lw_c[20:4] == p_dst[22:6]"),
    ("merged_byte_in_the_wrong_lane", "zm_blit_pxq.v", "c_data[{h_dst[1:0], 3'b000} +: 8]", "c_data[{~h_dst[1:0], 3'b000} +: 8]"),
    # the row walk (zm_blit_row): the first row from a settled box, the next one in the op's direction
    # (the check's box now settles 6 clocks before `go`, not 3: reading it a stage late is no longer a bug)
    ("first_row_without_its_product", "zm_blit_row.v", "(fx ? xo_fx : -xo) + s_prod[22:0];", "(fx ? xo_fx : -xo);"),
    ("row_walk_ignores_the_direction", "zm_blit_row.v", "s_str3 <= dn ^ fy ? -str : str;", "s_str3 <= fy ? -str : str;"),
    ("row_walk_never_moves", "zm_blit_row.v", "wire moved = y == ry_nx;", "wire moved = 1'b0;"),
    ("source_origin_x_ignored", "zm_blit_row.v", "(fx ? xo_fx : -xo)", "(fx ? xo_fx : 23'd0)"),
    ("upward_line_walks_down", "zm_blit_core.v", "is_line && !(sx(f_y0) < sx(f_y1))", "1'b0"),
    # CHISEL v2: AFFINE / MAP (zm_blit_tex, _tfetch, _rdmux)
    ("tex_clip_ignored", "zm_blit_tex.v", "t1v && !(tclip && (t1u > umask || t1t > vmask));", "t1v;"),
    ("tex_v_mask_ignored", "zm_blit_tex.v", "t2v_ <= t1t & vmask;", "t2v_ <= t1t;"),
    ("affine_u_never_steps", "zm_blit_tex.v", "u <= u + du;", "u <= u;"),
    ("affine_left_of_the_clip_drawn", "zm_blit_tex.v", "wire vis = x >= cx0;", "wire vis = 1'b1;"),
    ("affine_span_rows_unclipped_below", "zm_blit_tex.v", "(y < cy0 || y >= cy1)", "(y < cy0)"),
    ("map_first_half_ignores_the_row", "zm_blit_tex.v", "list[1] ^ (yo[0] & ms[1]) ^ xo[0]", "list[1] ^ xo[0]"),
    ("map_u_offset_ignored", "zm_blit_tex.v", "q_w[7:0]} + uoff;", "q_w[7:0]};"),
    ("map_row_offset_mixes_signs", "zm_blit_tfetch.v", "p <= dy0 * ms;", "p <= (ey0 - y0) * ms;"),
    ("fetch_overruns_its_fifo", "zm_blit_tfetch.v", "st == RUN && used < 5'd16", "st == RUN"),
    ("aux_answer_routed_by_the_newest", "zm_blit_rdmux.v", "assign aux_rsp = rd_rsp_valid && who[rp];",
     "assign aux_rsp = rd_rsp_valid && who[wp - 6'd1];"),
    ("affine_c_reads_not_ordered", "zm_blit_core.v", "ord_c <= is_aff && (c_dep || coll_en);", "ord_c <= 1'b0;"),
    ("affine_collision_reads_not_ordered", "zm_blit_core.v", "(c_dep || coll_en)", "(c_dep)"),
    ("tex_texture_extent_unchecked", "zm_blit_chk.v", "!sel ? {4'd0, {1'b0, umask} + 17'd1}", "!sel ? 21'd1"),
    ("span_list_alignment_unchecked", "zm_blit_chk.v", "is_aff ? s_base[1:0] == 2'd0", "is_aff ? 1'b1"),
    # CHISEL v2: mirror, area fill, collision
    ("mirror_x_ignored", "zm_blit_row.v", "assign addr = back ? cur - xx : cur + xx;", "assign addr = cur + xx;"),
    ("mirror_y_walks_the_rows_forward", "zm_blit_row.v", "s_str3 <= dn ^ fy ? -str : str;", "s_str3 <= dn ? -str : str;"),
    ("mirror_y_starts_at_the_top", "zm_blit_row.v", "s_j <= fy ? yorg + $signed({2'b00, h}) - 18'sd1 - ys : ys - yorg;",
     "s_j <= ys - yorg;"),
    ("mirror_keeps_the_behind_rule", "zm_blit_chk.v", "!is_tex && !mirror &&", "!is_tex &&"),
    ("fill_carry_not_reset_per_row", "zm_blit_pxq.v", "wire [7:0] cin = h_row ? carry0 : carry;", "wire [7:0] cin = carry;"),
    ("fill_inclusive_is_exclusive", "zm_blit_pxq.v", "fill[0] ? cin | res", "fill[0] ? cin ^ res"),
    ("fill_keyed_pixel_toggles", "zm_blit_pxq.v", "carry <= cin ^ (h_wr ? res : 8'd0);", "carry <= cin ^ res;"),
    ("fill_keeps_the_nop_shortcut", "zm_blit_core.v", "is_tex || fill_on || coll_en ? 1'b0", "is_tex || coll_en ? 1'b0"),
    ("collision_reads_no_c", "zm_blit_px.v", "need = {cen && !c_dc || force_c,", "need = {cen && !c_dc,"),
    ("collision_on_any_write", "zm_blit_pxq.v", "h_wr && h_c != 8'd0;", "h_wr;"),
    # (the minterm sees C through cen: an unread C's stale byte can no longer show, so the old
    # unread_channel_keeps_a_stale_byte mutant is equivalent now; this one breaks the mask itself)
    ("collision_c_feeds_the_minterm", "zm_blit_pxq.v", "mt[{h_a[i], bval[i], cen && h_c[i]}]", "mt[{h_a[i], bval[i], h_c[i]}]"),
    ("collision_kept_across_kicks", "zm_blit_regs.v", "if (rst || kick) coll <= 1'b0;", "if (rst) coll <= 1'b0;"),
    ("desc_blit_first_dest_row_is_the_top", "zm_blit_core.v", "is_blit && f_con[6] ? ey1 - 18'sd1 : ", ""),
]


def _run(cmd: list[str], cwd: Path = BUILD) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=900, check=False)


def build_tb(root: Path = FPGA, out: Path = BUILD) -> Path:
    """The testbench over the RTL under `root` (the real tree, or a mutated copy), built in `out`."""
    out.mkdir(parents=True, exist_ok=True)
    reads = " ".join(str(root / "rtl/blitter" / f) for f in RTL)
    incs = f"-I{FPGA / 'gen'} -I{root / 'rtl/blitter'}"
    script = f"read_verilog {incs} {reads}; hierarchy -top zm_blit; proc; write_cxxrtl {out / 'zm_blit.cc'}"
    assert yowasp_yosys.run_yosys(["-q", "-p", script]) == 0, "yosys failed on zm_blit"
    exe = out / "blitter_tb"
    cmd = [
        "clang++",
        "-std=c++17",
        "-O2",
        f"-I{test_rtl.CXXRTL_INCLUDE}",
        f"-I{out}",
        str(FPGA / "tests/tb/blitter_tb.cpp"),
    ]
    subprocess.run([*cmd, "-o", str(exe)], check=True)
    return exe


@pytest.fixture(scope="module")
def oracle() -> dict[str, Path]:
    """The Zig oracle, the scripts, and the oracle's trace of each."""
    BUILD.mkdir(parents=True, exist_ok=True)
    root, blit = FPGA / "tests/blitter_ref/blitter_ref.zig", FPGA.parent / "machine/blitter.zig"
    cmd = [ZIG, "build-exe", "-OReleaseSafe", "-lc", "--dep", "blitter", f"-Mroot={root}", f"-Mblitter={blit}"]
    subprocess.run([*cmd, f"-femit-bin={BUILD / 'blitter_ref'}"], check=True, cwd=BUILD)
    for name, make in SCRIPTS.items():
        (BUILD / f"{name}.txt").write_text("\n".join(make().lines) + "\n")
        r = _run([str(BUILD / "blitter_ref"), f"{name}.txt", f"{name}.trace"])
        assert r.returncode == 0, r.stderr
    return {name: BUILD / f"{name}.trace" for name in SCRIPTS}


@pytest.fixture(scope="module")
def tb() -> Path:
    return build_tb()


def _trace(path: Path) -> list[list[str]]:
    return [line.split() for line in path.read_text().splitlines()]


def test_the_scripts_exercise_every_op(oracle: dict[str, Path]) -> None:
    """A script that stops drawing proves nothing: each op must draw, in each script's trace."""
    ran = {"edges": 80, "random1": 380, "random2": 380, "tex1": 300}
    for name, trace in oracle.items():
        if name not in ran:
            continue
        script = [line.split() for line in (BUILD / f"{name}.txt").read_text().splitlines() if line.startswith("run")]
        rows = _trace(trace)
        assert len(rows) >= ran[name]
        for cmd in ("1", "2", "3", "4") + (("6", "7") if name.startswith("tex") else ()):
            drew = sum(1 for (_, c), r in zip(script, rows, strict=True) if c == cmd and int(r[2]) > 0)
            assert drew >= 10, f"{name}: only {drew} ops of command {cmd} drew anything"
        assert any(r[2] == "0" for r in rows), f"{name}: no op was refused"


def test_the_queue_script_runs_lists_that_draw_and_lists_refused(oracle: dict[str, Path]) -> None:
    script = [line.split() for line in (BUILD / "queue1.txt").read_text().splitlines() if line.startswith("run")]
    rows = _trace(oracle["queue1"])
    lists = [r for (_, c), r in zip(script, rows, strict=True) if c == "5"]
    assert len(lists) == 40
    assert sum(int(r[2]) > 0 for r in lists) >= 30, "most lists must draw"
    assert any(r[2] == "0" for r in lists), "no list was refused or drew nothing"


@pytest.mark.parametrize("mode", ["fast", "random", "deep"])
@pytest.mark.parametrize("name", list(SCRIPTS))
def test_the_rtl_matches_the_machine(name: str, mode: str, tb: Path, oracle: dict[str, Path]) -> None:
    r = _run([str(tb), f"{name}.txt", str(oracle[name]), mode, "11"])
    print(r.stdout)
    assert r.returncode == 0, r.stdout + r.stderr


OP_CLOCKS = 48  # a kick's fixed clocks: the tap copy (24), the checks, the drain


def test_in_plane_copies_run_unordered_where_no_read_can_alias(oracle: dict[str, Path], tb: Path) -> None:
    """The oracle cannot see `ordered` (both orders leave the same pixels): bound the clocks.
    In `fast` memory a provably safe copy runs near a pixel a clock, an ordered one waits for
    each write; the hash still has to match, and `deep` proves the fast ones safe."""
    _, ops = speed_script()
    r = _run([str(tb), "speed.txt", str(oracle["speed"]), "fast", "11", "speed.out"])
    assert r.returncode == 0, r.stdout
    clocks = [int(line.split()[6]) for line in (BUILD / "speed.out").read_text().splitlines()]
    for (name, fast), clk in zip(ops, clocks, strict=True):
        per_px = (clk - OP_CLOCKS) / (W * (1 if "one row" in name else H))
        print(f"{name}: {per_px:.2f} clocks a pixel")
        assert (per_px < 1.6) if fast else (per_px > 2.5), f"{name}: {per_px:.2f} clocks a pixel"


@pytest.mark.skipif(os.environ.get("ZM_RTL_BREAK") != "1", reason="set ZM_RTL_BREAK=1 to run the break tests")
@pytest.mark.parametrize(("name", "file", "old", "new"), MUTANTS, ids=[m[0] for m in MUTANTS])
def test_a_broken_rule_is_caught(name: str, file: str, old: str, new: str, oracle: dict[str, Path]) -> None:
    # Under fpga/build, not tmp: yowasp's Yosys is wasm and sees only this tree.
    work = FPGA / "build" / "tests" / "mutants" / f"blit_{name}"
    shutil.rmtree(work, ignore_errors=True)
    (work / "rtl/blitter").mkdir(parents=True)
    for f in FILES:
        shutil.copy(FPGA / "rtl/blitter" / f, work / "rtl/blitter" / f)
    text = (work / "rtl/blitter" / file).read_text()
    assert text.count(old) == 1, f"{name}: the text to break is not unique in {file}"
    (work / "rtl/blitter" / file).write_text(text.replace(old, new))
    exe = build_tb(work, work)
    # random first; deep (reads 16-31 clocks late, many in flight) only if random missed it
    caught = any(
        _run([str(exe), f"{n}.txt", str(oracle[n]), mode, "11"]).returncode != 0
        for mode in ("random", "deep")
        for n in SCRIPTS
    )
    assert caught, f"{name} went unnoticed"
