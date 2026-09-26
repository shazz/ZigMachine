// ---------------------------------------------------------------------------
// zigmachine_mem.rs — the machine's RAM arena (HW 1.7.0) for a Rust cart.
//
// The Rust twin of apps/c/zigmachine_mem.h. malloc for a cart: zeroed memory
// above the cart's static data + stack, below the video region. Prefer it to a
// big `static mut BUF: [u8; N] = [0; N]`, which the linker writes out byte for
// byte into the cart binary (imported memory is not known to be zero) and which
// counts against the 2 MiB window before the cart runs (apps/zero_segments.mjs
// fails the build on a zero run of 64 KB+).
//
//     mod zigmachine_mem;
//     let work: &'static mut [u16] = zigmachine_mem::alloc::<u16>(320 * 200)?; // zeroed
//     let m = zigmachine_mem::mark();  ...  unsafe { zigmachine_mem::release(m) };
//
// Nothing is freed singly. A new cart (boot, swap) starts with an empty arena.
// See docs/MEMORY.md and machine/sdk/hardware.zig.
// ---------------------------------------------------------------------------
#![allow(dead_code)] // a cart uses the part it needs

#[link(wasm_import_module = "env")]
extern "C" {
    fn hwRamAlloc(bytes: u32, alignment: u32) -> u32;
    fn hwRamMark() -> u32;
    fn hwRamRelease(mark: u32);
    fn hwRamAllocFailures() -> u32;
    fn hwRamFree() -> u32;
}

/// A position in the arena; release() frees everything allocated after it.
#[derive(Clone, Copy)]
pub struct Mark(u32);

/// `n` zeroed Ts aligned for T, or None when the window cannot hold them (the
/// machine counts the refusal: failures()). The slice lives until a release()
/// to a mark taken before it, or until the cart is replaced.
pub fn alloc<T: Copy>(n: usize) -> Option<&'static mut [T]> {
    // Past u32 the machine still sees the request, so it is refused AND counted.
    let bytes = n
        .checked_mul(core::mem::size_of::<T>())
        .and_then(|b| u32::try_from(b).ok())
        .unwrap_or(u32::MAX);
    if bytes == 0 {
        return Some(&mut []);
    }
    // SAFETY: hwRamAlloc returns 0 or `bytes` zeroed bytes aligned to T, owned
    // by nobody else until a release(); zero is a valid bit pattern for the
    // plain-data (Copy) Ts this is meant for.
    let at = unsafe { hwRamAlloc(bytes, core::mem::align_of::<T>() as u32) };
    if at == 0 {
        return None;
    }
    Some(unsafe { core::slice::from_raw_parts_mut(at as usize as *mut T, n) })
}

pub fn mark() -> Mark {
    Mark(unsafe { hwRamMark() })
}

/// Free everything allocated after `m`.
///
/// # Safety
/// Every slice alloc() returned after `m` is dangling afterwards.
pub unsafe fn release(m: Mark) {
    hwRamRelease(m.0)
}

/// Refused requests since this cart was loaded. Non-zero = a bug.
pub fn failures() -> u32 {
    unsafe { hwRamAllocFailures() }
}

/// Bytes left in the window above the arena.
pub fn free() -> u32 {
    unsafe { hwRamFree() }
}
