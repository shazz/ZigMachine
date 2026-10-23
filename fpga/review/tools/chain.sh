#!/bin/bash
# Review evidence chain: 1) per-block OOC sweeps, 2) full-SoC Vivado postmortem (current tree).
set -u
export PATH=/opt/vivado/2026.1/Vivado/bin:$PATH LD_LIBRARY_PATH=$HOME/.local/lib/vivado-compat
FPGA=/home/matt/projects/ZigMachine/fpga
RW=/tmp/opencode/rev
cd "$FPGA" || exit 1
mkdir -p "$RW/ooc"
rm -rf "$RW/ooc"/*
V="$FPGA/review/tools/ooc_sweep.sh"
"$V" zm_video_plane 8.0    "$RW/ooc/plane_8ns"        rtl/video/zm_video_plane.v; echo "[chain] plane_8ns rc=$?"
"$V" zm_video_plane 6.67   "$RW/ooc/plane_6.67ns"     rtl/video/zm_video_plane.v; echo "[chain] plane_6.67ns rc=$?"
"$V" zm_blit_px    10.0    "$RW/ooc/blit_px_10ns"     rtl/blitter/zm_blit_px.v rtl/blitter/zm_blit_pxq.v; echo "[chain] blit_px_10ns rc=$?"
"$V" zm_blit_px    6.67    "$RW/ooc/blit_px_6.67ns"   rtl/blitter/zm_blit_px.v rtl/blitter/zm_blit_pxq.v; echo "[chain] blit_px_6.67ns rc=$?"
"$V" zm_video_mix  8.0     "$RW/ooc/mix_8ns"          rtl/video/zm_video_mix.v rtl/video/zm_video_sdpram.v; echo "[chain] mix_8ns rc=$?"
"$V" zm_audio_soc  10.0    "$RW/ooc/audio_soc_10ns"   rtl/audio/zm_audio_soc.v rtl/audio/zm_audio_core.v rtl/audio/zm_audio_frac.v rtl/audio/zm_audio_ym.v rtl/audio/zm_audio_pokey.v rtl/audio/zm_audio_pcm.v rtl/audio/zm_audio_mix.v rtl/audio/zm_audio_sched.v rtl/audio/zm_audio_fifo.v rtl/video/zm_video_sdpram.v rtl/audio/zm_pokey.v rtl/audio/zm_pokey_pair.v rtl/audio/zm_pokey_poly.v third_party/jt49/hdl/jt49.v third_party/jt49/hdl/jt49_cen.v third_party/jt49/hdl/jt49_div.v third_party/jt49/hdl/jt49_eg.v third_party/jt49/hdl/jt49_exp.v third_party/jt49/hdl/jt49_noise.v; echo "[chain] audio_soc_10ns rc=$?"
echo "+$(date +%T) step 1 done"
rm -rf "$RW/pletdir"
bash "$FPGA/review/tools/synth_full.sh"; echo "[chain] synth_full rc=$?"
echo "+$(date +%T) step 2 done"
