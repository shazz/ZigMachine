// ---------------------------------------------------------------------------
// zigmachine_music.rs — let a Rust cart ask the host for a tune, BY NAME.
//
// The Rust twin of apps/c/zigmachine_music.h, and the same song bridge the Zig
// scenes use (libs/zig/zigos.zig requestSong / requestSongTune). Nothing here
// plays music: the SNDH player lives in demo-audio.wasm on the audio thread.
// The cart only leaves a request in shared memory; docs/sealed-loader.js polls
// the four exports below every frame, fetches docs/music/<name>, and the
// extension picks the player (.sndh / .mod / .ymraw / .raw).
//
//     mod zigmachine_music;
//     zigmachine_music::request_song("sos.sndh");
//
// Declaring the module DEFINES the four exports, so do it once per cart.
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

/// Request subtune `tune` of `name` (a file under docs/music/). Subtunes count
/// from 1; 0 means "the image's own default". Only an SNDH has subtunes.
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
    }
    true
}

/// Request `name` at its default subtune.
pub fn request_song(name: &str) -> bool {
    request_song_tune(name, 0)
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
