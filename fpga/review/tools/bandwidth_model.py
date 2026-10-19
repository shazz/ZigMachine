#!/usr/bin/env python3
"""bandwidth_model.py: Analytical and empirical DDR3 / AXI HP bandwidth model for ZigMachine on XC7Z010.

Computes exact bandwidth and transaction profiles across all 4 HP ports:
- HP0: Cart CPU (I-cache refill, D-cache refill, D-cache write-through)
- HP1: Video DMA (Compositor PFB/Picture row load & store, plane fetch, scanout display fetch)
- HP2: Hardware Blitter (Sources A/B/C read, Dest D write, single-beat overhead)
- HP3: Audio Core & Sound CPU (PCM stereo stream, BARD/Musashi emulation memory traffic)
"""

from __future__ import annotations
import argparse
import json
from dataclasses import asdict, dataclass
from typing import Dict, List, Tuple


# Zynq-7000 DDR3-1066 Controller Parameters
DDR3_CLOCK_MHZ = 533.333
DDR3_DATA_RATE_MTS = 1066.667
DDR3_BUS_WIDTH_BYTES = 2  # 16-bit physical bus on MicroPhase Z7-Lite
DDR3_PEAK_MB_S = DDR3_DATA_RATE_MTS * DDR3_BUS_WIDTH_BYTES  # 2133.333 MB/s

# Video Constants
RASTER_WIDTH = 800
RASTER_HEIGHT = 280
FRAME_RATE_HZ = 60.0
FRAME_TIME_MS = 1000.0 / FRAME_RATE_HZ  # 16.667 ms
BYTES_PER_PFB_ROW = 800 * 4  # 3200 bytes (400 64-bit beats)
BYTES_PER_PIC_ROW = 800 * 4  # 3200 bytes (400 64-bit beats)


@dataclass
class MasterTraffic:
    name: str
    port: str
    read_mb_frame: float
    write_mb_frame: float
    read_mb_s: float
    write_mb_s: float
    total_mb_s: float
    read_tx_per_frame: int
    write_tx_per_frame: int
    avg_read_burst_bytes: float
    avg_write_burst_bytes: float
    notes: str


@dataclass
class CartProfile:
    name: str
    planes: int
    cart_stores_per_frame: int
    cart_i_refills_per_frame: int
    cart_d_refills_per_frame: int
    blitter_pixels_per_frame: int
    blitter_channels: int  # 1 (fill), 2 (copy), 3 (masked), 4 (minterm with C)
    sound_active: bool
    sound_cpu: bool
    sound_stores_per_frame: int
    sound_refills_per_frame: int


# Known profiles from CYCLES.md, FPGA_SOUND_CPU.md, and video.mk
KNOWN_CARTS: Dict[str, CartProfile] = {
    "tutorial": CartProfile(
        name="tutorial",
        planes=1,
        cart_stores_per_frame=25_000,
        cart_i_refills_per_frame=1_200,
        cart_d_refills_per_frame=400,
        blitter_pixels_per_frame=0,
        blitter_channels=1,
        sound_active=True,
        sound_cpu=False,
        sound_stores_per_frame=0,
        sound_refills_per_frame=0,
    ),
    "union_beatdis": CartProfile(
        name="union_beatdis",
        planes=3,
        cart_stores_per_frame=125_000,
        cart_i_refills_per_frame=3_500,
        cart_d_refills_per_frame=1_800,
        blitter_pixels_per_frame=80_000,
        blitter_channels=2,
        sound_active=True,
        sound_cpu=True,
        sound_stores_per_frame=330_000,
        sound_refills_per_frame=50_000,
    ),
    "blitter_demo": CartProfile(
        name="blitter_demo",
        planes=1,
        cart_stores_per_frame=15_000,
        cart_i_refills_per_frame=2_000,
        cart_d_refills_per_frame=800,
        blitter_pixels_per_frame=350_000,
        blitter_channels=2,
        sound_active=False,
        sound_cpu=False,
        sound_stores_per_frame=0,
        sound_refills_per_frame=0,
    ),
    "tsl_hybridglenz": CartProfile(
        name="tsl_hybridglenz",
        planes=2,
        cart_stores_per_frame=45_000,
        cart_i_refills_per_frame=4_000,
        cart_d_refills_per_frame=2_000,
        blitter_pixels_per_frame=750_000,
        blitter_channels=3,
        sound_active=True,
        sound_cpu=True,
        sound_stores_per_frame=150_000,
        sound_refills_per_frame=25_000,
    ),
    "skystrike": CartProfile(
        name="skystrike",
        planes=2,
        cart_stores_per_frame=180_000,
        cart_i_refills_per_frame=5_200,
        cart_d_refills_per_frame=2_800,
        blitter_pixels_per_frame=120_000,
        blitter_channels=2,
        sound_active=True,
        sound_cpu=True,
        sound_stores_per_frame=120_000,
        sound_refills_per_frame=20_000,
    ),
    "polkadots_fixed": CartProfile(
        name="polkadots_fixed",
        planes=1,
        cart_stores_per_frame=85_000,
        cart_i_refills_per_frame=3_100,
        cart_d_refills_per_frame=1_500,
        blitter_pixels_per_frame=0,
        blitter_channels=1,
        sound_active=False,
        sound_cpu=False,
        sound_stores_per_frame=0,
        sound_refills_per_frame=0,
    ),
    "polkadots_4k_thrash": CartProfile(
        name="polkadots_4k_thrash",
        planes=1,
        cart_stores_per_frame=250_000,
        cart_i_refills_per_frame=792_000,
        cart_d_refills_per_frame=50_000,
        blitter_pixels_per_frame=0,
        blitter_channels=1,
        sound_active=False,
        sound_cpu=False,
        sound_stores_per_frame=0,
        sound_refills_per_frame=0,
    ),
    "worst_synthetic": CartProfile(
        name="worst_synthetic",
        planes=4,
        cart_stores_per_frame=350_000,
        cart_i_refills_per_frame=50_000,
        cart_d_refills_per_frame=20_000,
        blitter_pixels_per_frame=1_200_000,
        blitter_channels=4,
        sound_active=True,
        sound_cpu=True,
        sound_stores_per_frame=350_000,
        sound_refills_per_frame=50_000,
    ),
}


def model_bandwidth(profile: CartProfile) -> Tuple[List[MasterTraffic], float, float]:
    """Computes traffic for each master and total bandwidth & DDR utilization."""
    results: List[MasterTraffic] = []

    # 1. HP0: Cart CPU
    # Refills are 32 bytes (4 beats of 64-bit)
    cpu_rd_bytes = (profile.cart_i_refills_per_frame + profile.cart_d_refills_per_frame) * 32
    # Stores are 4 bytes each (1 beat 32-bit WR32)
    cpu_wr_bytes = profile.cart_stores_per_frame * 4
    cpu_rd_tx = profile.cart_i_refills_per_frame + profile.cart_d_refills_per_frame
    cpu_wr_tx = profile.cart_stores_per_frame
    cpu_rd_mb = (cpu_rd_bytes * FRAME_RATE_HZ) / 1e6
    cpu_wr_mb = (cpu_wr_bytes * FRAME_RATE_HZ) / 1e6

    results.append(MasterTraffic(
        name="Cart CPU",
        port="HP0",
        read_mb_frame=cpu_rd_bytes / 1e6,
        write_mb_frame=cpu_wr_bytes / 1e6,
        read_mb_s=cpu_rd_mb,
        write_mb_s=cpu_wr_mb,
        total_mb_s=cpu_rd_mb + cpu_wr_mb,
        read_tx_per_frame=cpu_rd_tx,
        write_tx_per_frame=cpu_wr_tx,
        avg_read_burst_bytes=32.0,
        avg_write_burst_bytes=4.0,
        notes=f"Refills: {cpu_rd_tx:,}, Stores: {cpu_wr_tx:,}"
    ))

    # 2. HP1: Video DMA (Compositor + Scanout)
    # A. Scanout fetch: 280 lines * 3200 bytes, burst of 400 beats (16-beat AXI chunks)
    scanout_bytes = RASTER_HEIGHT * BYTES_PER_PIC_ROW
    scanout_tx = RASTER_HEIGHT * (BYTES_PER_PIC_ROW // 128)  # 128-byte burst max

    # B. Compositor Row I/O & Plane fetches:
    # BG pass: if planes > 0 and fused clear: 0 BG lines. If not fused: 280 lines * 3200 bytes write.
    # Planes:
    # - Plane 0 (first): Read PFB (3200), Read source (320-400), Write PFB (3200), Write Pic (3200)
    # - Plane 1..N: Read PFB (3200), Read Pic (3200), Read source (320-400), Write PFB (3200), Write Pic (3200)
    comp_rd_bytes = 0
    comp_wr_bytes = 0
    comp_rd_tx = 0
    comp_wr_tx = 0

    num_planes = max(1, profile.planes)
    for p in range(num_planes):
        plane_source_bytes = RASTER_HEIGHT * 400  # typical plane stride
        plane_source_tx = RASTER_HEIGHT * 4
        if p == 0:
            rd_line = BYTES_PER_PFB_ROW + 400
            wr_line = BYTES_PER_PFB_ROW + BYTES_PER_PIC_ROW
        else:
            rd_line = BYTES_PER_PFB_ROW + BYTES_PER_PIC_ROW + 400
            wr_line = BYTES_PER_PFB_ROW + BYTES_PER_PIC_ROW

        comp_rd_bytes += RASTER_HEIGHT * rd_line
        comp_wr_bytes += RASTER_HEIGHT * wr_line
        comp_rd_tx += RASTER_HEIGHT * ((rd_line + 127) // 128)
        comp_wr_tx += RASTER_HEIGHT * ((wr_line + 63) // 64)

    v_rd_bytes = scanout_bytes + comp_rd_bytes
    v_wr_bytes = comp_wr_bytes
    v_rd_tx = scanout_tx + comp_rd_tx
    v_wr_tx = comp_wr_tx
    v_rd_mb = (v_rd_bytes * FRAME_RATE_HZ) / 1e6
    v_wr_mb = (v_wr_bytes * FRAME_RATE_HZ) / 1e6

    results.append(MasterTraffic(
        name=f"Video DMA ({num_planes}p + Scanout)",
        port="HP1",
        read_mb_frame=v_rd_bytes / 1e6,
        write_mb_frame=v_wr_bytes / 1e6,
        read_mb_s=v_rd_mb,
        write_mb_s=v_wr_mb,
        total_mb_s=v_rd_mb + v_wr_mb,
        read_tx_per_frame=v_rd_tx,
        write_tx_per_frame=v_wr_tx,
        avg_read_burst_bytes=v_rd_bytes / max(1, v_rd_tx),
        avg_write_burst_bytes=v_wr_bytes / max(1, v_wr_tx),
        notes=f"Scanout: {scanout_bytes/1e6*60:.1f} MB/s, Comp Row I/O: {(comp_rd_bytes+comp_wr_bytes)/1e6*60:.1f} MB/s"
    ))

    # 3. HP2: Blitter
    # In zm_blit_px: 4 pixels share a word if contiguous, but non-contiguous / line / tri
    # averages ~2.5 pixels per word read and 2.5 pixels per word write.
    # Reads: (channels - 1) source channels. Each channel read = 64-bit beat (8 bytes).
    # Writes: 1 dest channel. Each dest write = 32-bit beat (4 bytes) WR32.
    px = profile.blitter_pixels_per_frame
    ch = profile.blitter_channels
    src_channels = max(0, ch - 1)

    words_accessed = int(px / 2.5) if px > 0 else 0
    blit_rd_bytes = words_accessed * src_channels * 8
    blit_wr_bytes = words_accessed * 4
    blit_rd_tx = words_accessed * src_channels  # each distinct word read is 1 transaction!
    blit_wr_tx = words_accessed  # each distinct word write is 1 transaction!
    blit_rd_mb = (blit_rd_bytes * FRAME_RATE_HZ) / 1e6
    blit_wr_mb = (blit_wr_bytes * FRAME_RATE_HZ) / 1e6

    results.append(MasterTraffic(
        name=f"Blitter ({px:,} px, {ch}ch)",
        port="HP2",
        read_mb_frame=blit_rd_bytes / 1e6,
        write_mb_frame=blit_wr_bytes / 1e6,
        read_mb_s=blit_rd_mb,
        write_mb_s=blit_wr_mb,
        total_mb_s=blit_rd_mb + blit_wr_mb,
        read_tx_per_frame=blit_rd_tx,
        write_tx_per_frame=blit_wr_tx,
        avg_read_burst_bytes=8.0 if blit_rd_tx > 0 else 0.0,
        avg_write_burst_bytes=4.0 if blit_wr_tx > 0 else 0.0,
        notes=f"Single-beat overhead: {blit_rd_tx+blit_wr_tx:,} AXI cmds/frame"
    ))

    # 4. HP3: Audio & Sound CPU
    # PCM streaming: 48 kHz * 4 bytes = 192 KB/s
    pcm_rd_bytes = int(48000 * 4 / FRAME_RATE_HZ) if profile.sound_active else 0
    pcm_rd_tx = RASTER_HEIGHT  # polled periodically
    # Sound CPU (if active)
    snd_rd_bytes = pcm_rd_bytes
    snd_wr_bytes = 0
    snd_rd_tx = pcm_rd_tx
    snd_wr_tx = 0
    if profile.sound_cpu:
        snd_cpu_rd_bytes = profile.sound_refills_per_frame * 32
        snd_cpu_wr_bytes = profile.sound_stores_per_frame * 4
        snd_rd_bytes += snd_cpu_rd_bytes
        snd_wr_bytes += snd_cpu_wr_bytes
        snd_rd_tx += profile.sound_refills_per_frame
        snd_wr_tx += profile.sound_stores_per_frame

    snd_rd_mb = (snd_rd_bytes * FRAME_RATE_HZ) / 1e6
    snd_wr_mb = (snd_wr_bytes * FRAME_RATE_HZ) / 1e6

    results.append(MasterTraffic(
        name="Audio Core + Sound CPU" if profile.sound_cpu else "Audio Core (PCM only)",
        port="HP3",
        read_mb_frame=snd_rd_bytes / 1e6,
        write_mb_frame=snd_wr_bytes / 1e6,
        read_mb_s=snd_rd_mb,
        write_mb_s=snd_wr_mb,
        total_mb_s=snd_rd_mb + snd_wr_mb,
        read_tx_per_frame=snd_rd_tx,
        write_tx_per_frame=snd_wr_tx,
        avg_read_burst_bytes=32.0 if profile.sound_cpu else 8.0,
        avg_write_burst_bytes=4.0 if snd_wr_tx > 0 else 0.0,
        notes="BARD / Musashi SNDH" if profile.sound_cpu else "PCM stream 48kHz"
    ))

    # Totals
    total_mb_s = sum(m.total_mb_s for m in results)
    utilization_pct = (total_mb_s / DDR3_PEAK_MB_S) * 100.0

    return results, total_mb_s, utilization_pct


def run_all_profiles() -> Dict[str, dict]:
    summary = {}
    print("=" * 88)
    print(f"{'Cart Profile':<20} | {'Read MB/s':<10} | {'Write MB/s':<11} | {'Total MB/s':<11} | {'DDR3 Util %':<12}")
    print("=" * 88)

    for name, prof in KNOWN_CARTS.items():
        masters, total_mb_s, util_pct = model_bandwidth(prof)
        total_rd = sum(m.read_mb_s for m in masters)
        total_wr = sum(m.write_mb_s for m in masters)
        summary[name] = {
            "total_read_mb_s": round(total_rd, 2),
            "total_write_mb_s": round(total_wr, 2),
            "total_mb_s": round(total_mb_s, 2),
            "ddr_utilization_pct": round(util_pct, 2),
            "masters": [asdict(m) for m in masters]
        }
        print(f"{name:<20} | {total_rd:>10.2f} | {total_wr:>11.2f} | {total_mb_s:>11.2f} | {util_pct:>11.2f}%")

    print("=" * 88)
    return summary


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--json", help="Path to write JSON summary output")
    p.add_argument("--cart", help="Specific cart to detail")
    args = p.parse_args()

    summary = run_all_profiles()

    if args.cart and args.cart in summary:
        print(f"\n--- Detailed Breakdown for {args.cart} ---")
        for m in summary[args.cart]["masters"]:
            print(f"Port {m['port']} ({m['name']}):")
            print(f"  Read:  {m['read_mb_s']:.2f} MB/s ({m['read_tx_per_frame']:,} tx/frame, avg burst {m['avg_read_burst_bytes']:.1f} B)")
            print(f"  Write: {m['write_mb_s']:.2f} MB/s ({m['write_tx_per_frame']:,} tx/frame, avg burst {m['avg_write_burst_bytes']:.1f} B)")
            print(f"  Total: {m['total_mb_s']:.2f} MB/s | Notes: {m['notes']}")

    if args.json:
        with open(args.json, "w") as f:
            json.dump(summary, f, indent=2)
        print(f"Wrote summary JSON to {args.json}")


if __name__ == "__main__":
    main()
