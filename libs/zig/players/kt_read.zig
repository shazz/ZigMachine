// --------------------------------------------------------------------------
// A little-endian reader over a .kt image, as music.c's my_RWread / VER_READ
// see the file. Upstream reads past the end as "nothing read" and carries on
// with whatever the struct held; here running off the end refuses the song
// (error.Truncated), the one place the loader is stricter than upstream.
// --------------------------------------------------------------------------

pub const Error = error{ NotKt, Version, Truncated, TooManyChannels, TooLarge, BadFx, BadWave, BadSong };

/// A refusal's code, as the host reports it (audioKtError): 0 is "loaded".
pub fn code(e: Error) u32 {
    return switch (e) {
        error.NotKt => 1,
        error.Version => 2,
        error.Truncated => 3,
        error.TooManyChannels => 4,
        error.TooLarge => 5,
        error.BadFx => 6,
        error.BadWave => 7,
        error.BadSong => 8,
    };
}

pub const Reader = struct {
    data: []const u8,
    pos: usize = 0,
    version: u8 = 0,

    pub fn bytes(self: *Reader, n: usize) Error![]const u8 {
        if (n > self.data.len - self.pos) return error.Truncated;
        const b = self.data[self.pos..][0..n];
        self.pos += n;
        return b;
    }

    pub fn skip(self: *Reader, n: usize) Error!void {
        _ = try self.bytes(n);
    }

    pub fn u8_(self: *Reader) Error!u8 {
        return (try self.bytes(1))[0];
    }

    pub fn i8_(self: *Reader) Error!i8 {
        return @bitCast(try self.u8_());
    }

    pub fn u16_(self: *Reader) Error!u16 {
        const b = try self.bytes(2);
        return @as(u16, b[0]) | @as(u16, b[1]) << 8;
    }

    pub fn i16_(self: *Reader) Error!i16 {
        return @bitCast(try self.u16_());
    }

    pub fn u32_(self: *Reader) Error!u32 {
        const b = try self.bytes(4);
        return @as(u32, b[0]) | @as(u32, b[1]) << 8 | @as(u32, b[2]) << 16 | @as(u32, b[3]) << 24;
    }

    /// VER(file_version, first, last): this field is in the file at this version.
    pub fn has(self: *const Reader, first: u8) bool {
        return self.version >= first;
    }
};
