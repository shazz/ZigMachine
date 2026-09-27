// ---------------------------------------------------------------------------
// zigmachine_music.rs — let a Rust cart ask the host for a tune, BY NAME.
//
// The Rust twin of apps/c/zigmachine_music.h, and the same song bridge the Zig
// scenes use (libs/zig/zigos.zig requestSong / requestSongTune). Nothing here
// plays music: the SNDH player lives in demo-audio.wasm on the audio thread.
// The cart only leaves a request in shared memory; docs/sealed-loader.js polls
// the four exports below every frame, fetches docs/music/<name>, and the
// extension picks the player (.sndh / .mod / .ymraw / .raw). sndh_call() runs
// the PLAYING SNDH's INIT again (a game's sound effect) instead of reloading
// it; those calls are dropped, not kept, while sound is off.
//
//     mod zigmachine_music;
//     zigmachine_music::request_song("sos.sndh");
//
// Declaring the module DEFINES the exports (the four song ones and the four
// sndh-call ones), so do it once per cart.
// ---------------------------------------------------------------------------
#![allow(dead_code)] // a cart may use only one of the two request functions

use core::ptr::{addr_of, addr_of_mut};

/// Same capacity as zigos.zig's g_song_name. A longer name is refused, not
/// truncated: a cut-off filename would fetch the wrong file, or none, silently.
pub const SONG_NAME_MAX: usize = 64;
/// audioSndhPlay takes a u8, so a larger subtune cannot reach the player.
pub const SONG_TUNE_MAX: u32 = 255;

static mut NAME: [u8; SONG_NAME_MAX] = [0; SONG_NAME_MAX];
static mut LEN: u32 = 0;
static mut TUNE: u32 = 0;
static mut PENDING: bool = false;

/// sndh_call's queue: zg.sndhCall's (libs/zig/sndh_call.zig), same capacity
/// and rules.
pub const SNDH_CALL_MAX: usize = 16;
static mut CALL_NAME: [u8; SONG_NAME_MAX] = [0; SONG_NAME_MAX];
static mut CALL_LEN: u32 = 0;
static mut CALL_D0: [u32; SNDH_CALL_MAX] = [0; SNDH_CALL_MAX];
static mut CALL_N: usize = 0;
static mut CALL_DROPPED: u32 = 0;

/// Request subtune `tune` of `name` (a file under docs/music/). Subtunes count
/// from 1; 0 means "the image's own default". Only an SNDH has subtunes.
/// For a .mod, a tune of 32..255 is instead its start BPM (zg.requestModBpm);
/// 0..31 plays at ProTracker's 125.
/// Returns false when refused (empty or too-long name, or tune > 255).
/// A later request replaces a pending one.
pub fn request_song_tune(name: &str, tune: u32) -> bool {
    let bytes = name.as_bytes();
    if bytes.is_empty() || bytes.len() > SONG_NAME_MAX || tune > SONG_TUNE_MAX {
        return false;
    }
    // SAFETY: wasm32 carts are single-threaded; the host reads these only
    // between calls into the cart, never during one.
    unsafe {
        core::ptr::copy_nonoverlapping(bytes.as_ptr(), addr_of_mut!(NAME) as *mut u8, bytes.len());
        LEN = bytes.len() as u32;
        TUNE = tune;
        PENDING = true;
        CALL_N = 0; // this request reloads (or stops) what queued calls would run on
    }
    true
}

/// Run the playing SNDH's INIT again with d0 = `d0`, as a subroutine: no
/// reload, no chip or MFP reset, the replay clock and the timers' phase kept.
/// For sound effects, which a song request (a LOAD) would cut every voice for.
/// Every call of a frame reaches the tune, in order; a song request or stop
/// made after them discards them. If `name` is not the image playing, the host
/// loads it and d0 is its first INIT. False when refused (bad name, 16 already
/// this frame); refusals are counted in sndh_calls_dropped().
pub fn sndh_call(name: &str, d0: u16) -> bool {
    let bytes = name.as_bytes();
    // SAFETY: single-threaded, see request_song_tune.
    unsafe {
        if bytes.is_empty() || bytes.len() > SONG_NAME_MAX {
            CALL_DROPPED = CALL_DROPPED.wrapping_add(1);
            return false;
        }
        let queued = &*addr_of!(CALL_NAME);
        if CALL_N != 0 && &queued[..CALL_LEN as usize] != bytes {
            CALL_N = 0; // another image: the host loads it first
        }
        if CALL_N == SNDH_CALL_MAX {
            CALL_DROPPED = CALL_DROPPED.wrapping_add(1);
            return false;
        }
        if CALL_N == 0 {
            core::ptr::copy_nonoverlapping(bytes.as_ptr(), addr_of_mut!(CALL_NAME) as *mut u8, bytes.len());
            CALL_LEN = bytes.len() as u32;
        }
        (*addr_of_mut!(CALL_D0))[CALL_N] = d0 as u32;
        CALL_N += 1;
    }
    true
}

pub fn sndh_calls_dropped() -> u32 {
    unsafe { CALL_DROPPED }
}

/// Request `name` at its default subtune.
pub fn request_song(name: &str) -> bool {
    request_song_tune(name, 0)
}

/// Stop whatever is playing: "none" is the host's reserved stop name.
pub fn stop_song() -> bool {
    request_song("none")
}

// --- the exports the host polls (sealed-loader.js, once per frame) ----------
/// 1 = a new request is pending; reading it clears it, so each request plays once.
#[no_mangle]
pub extern "C" fn pollSongRequest() -> u32 {
    // SAFETY: single-threaded, see request_song_tune.
    unsafe {
        let p = PENDING;
        PENDING = false;
        p as u32
    }
}
#[no_mangle]
pub extern "C" fn songNamePtr() -> *const u8 {
    addr_of!(NAME) as *const u8
}
#[no_mangle]
pub extern "C" fn songNameLen() -> u32 {
    unsafe { LEN }
}
#[no_mangle]
pub extern "C" fn songTune() -> u32 {
    unsafe { TUNE }
}
/// The frame's sndh_call()s, polled after pollSongRequest: reading takes them.
#[no_mangle]
pub extern "C" fn pollSndhCalls() -> u32 {
    // SAFETY: single-threaded, see request_song_tune.
    unsafe {
        let n = CALL_N;
        CALL_N = 0;
        n as u32
    }
}
#[no_mangle]
pub extern "C" fn sndhCallD0(i: u32) -> u32 {
    let i = i as usize;
    if i < SNDH_CALL_MAX { unsafe { (*addr_of!(CALL_D0))[i] } } else { 0 }
}
#[no_mangle]
pub extern "C" fn sndhCallNamePtr() -> *const u8 {
    addr_of!(CALL_NAME) as *const u8
}
#[no_mangle]
pub extern "C" fn sndhCallNameLen() -> u32 {
    unsafe { CALL_LEN }
}
