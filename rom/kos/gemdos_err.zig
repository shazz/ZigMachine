// GEMDOS's answers (docs/KOS_GEMDOS.md §2): TOS's own negative codes, so a ported ST program's
// error checks read the same. Inside the library they are a Zig error set; the calls return code().
pub const E_OK: i32 = 0;
pub const ERROR: i32 = -1; // a generic error
pub const EWRITF: i32 = -10; // a write fault (C: full, or the host could not write)
pub const EREADF: i32 = -11; // a read fault (the drive answered nothing: a card gone, glass not serving)
pub const EWRPRO: i32 = -13; // write-protected (A:, and C: where the host serves no writes)
pub const EINVFN: i32 = -32; // an invalid function number or mode
pub const EFILNF: i32 = -33; // file not found
pub const EPTHNF: i32 = -34; // path not found
pub const ENHNDL: i32 = -35; // no handles left
pub const EACCDN: i32 = -36; // access denied (a write mode, a folder opened as a file)
pub const EIHNDL: i32 = -37; // an invalid handle
pub const EDRIVE: i32 = -46; // no such drive (or it did not mount)
pub const ENSAME: i32 = -48; // not the same drive (Frename)
pub const ENMFIL: i32 = -49; // no more files (Fsnext)
pub const ERANGE: i32 = -64; // out of range (Fseek past the end, a buffer too small)

pub const Error = error{ WriteFault, NotSameDrive, ReadFault, WriteProtect, InvalidFunction, FileNotFound, PathNotFound, NoHandles, AccessDenied, BadHandle, NoDrive, NoMoreFiles, Range };

pub fn code(e: Error) i32 {
    return switch (e) {
        error.WriteFault => EWRITF,
        error.NotSameDrive => ENSAME,
        error.ReadFault => EREADF,
        error.WriteProtect => EWRPRO,
        error.InvalidFunction => EINVFN,
        error.FileNotFound => EFILNF,
        error.PathNotFound => EPTHNF,
        error.NoHandles => ENHNDL,
        error.AccessDenied => EACCDN,
        error.BadHandle => EIHNDL,
        error.NoDrive => EDRIVE,
        error.NoMoreFiles => ENMFIL,
        error.Range => ERANGE,
    };
}

/// A call's answer: its value, or its error's code.
pub fn answer(r: Error!i32) i32 {
    return r catch |e| code(e);
}
