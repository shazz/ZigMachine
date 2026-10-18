// --------------------------------------------------------------------------
// Where the XM mixer writes each block of a Paula channel: a ring, never the
// same bytes twice in a row.
//
// Why: the mixer rebuilds a channel's buffer every block (a tick, or part of
// one) and triggers the channel on it. In the browser the sealed chip mixes
// that buffer at once (machineMixPaula), so one buffer reused per block was
// enough. On the board the chip is the audio core (CHORUS): the trigger is a
// STAMPED write, played when the sound reaches it, a lead of up to four
// frames after the player wrote it (fpga/host/audio_queue.h zma_lead,
// fpga/cycles/baudio.c). With one buffer, three or four later blocks had
// overwritten it by then, and the core played that: noise. So each block
// takes the next span of a ring that holds more than the lead plus the
// largest block, and a block's bytes stay intact until it has been heard.
// The output in the browser is unchanged (the same samples, read at once).
// Pure: no chip. Tested natively (xm_ring_test.zig).
// --------------------------------------------------------------------------

/// The ring's frames per Paula channel (one byte a frame, signed 8-bit).
pub const FRAMES: u32 = 16384;

/// The board's longest lead in samples: four 60 Hz frames of 735
/// (fpga/host/audio_queue.h zma_lead). A block written is played at most this
/// many samples (plus its own length) after the player rendered it.
pub const BOARD_LEAD: u32 = 4 * 735;

/// The start of the next block of `block` frames, the write position at `pos`:
/// contiguous (a trigger plays one span), so a block that would run past the
/// end starts again at 0. The caller moves `pos` to start + block.
pub fn place(pos: u32, block: u32) u32 {
    return if (pos + block > FRAMES) 0 else pos;
}
