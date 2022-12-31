//
// from https://github.com/luickk/zig-png-decoder
//
const consoleLog = @import("debug.zig").consoleLog;

const std = @import("std");

const magicNumbers = @import("magicnumbers.zig");

pub fn PngDecoder(comptime ReaderType: type) type {
    return struct {
        const Self = @This();

        const PngDecoderErr = error{ ChunkCrcErr, ChunkHeaderSigErr, ChunkOrderErr, MissingPngSig, ColorTypeNotSupported, CompressionNotSupported, FilterNotSupported, InterlaceNotSupported, CriticalChunkTypeNotSupported };

        const DecodedImg = struct {
            width: u32,
            height: u32,
            bit_depth: u8,
            img_size: usize,
            bitmap_reader: std.compress.zlib.ZlibStream(std.io.FixedBufferStream([]u8).Reader).Reader,

            color_type: magicNumbers.ColorType,
            compression_method: u8,
            filter_method: u8,
            interlace_method: u8,
        };

        pub const PngChunk = struct {
            img_reader: ReaderType,
            len: u32, // only defines len of the data field!
            temp_data_hash_buff: [4096]u8,
            chunk_type: ?magicNumbers.ChunkType,
            crc_hasher: std.hash.Crc32,

            pub fn init(img_reader: ReaderType) PngChunk {
                var chunk = PngChunk{
                    .img_reader = img_reader,
                    .len = 0,
                    .temp_data_hash_buff = undefined,
                    .chunk_type = null,
                    .crc_hasher = std.hash.Crc32.init(),
                };
                return chunk;
            }

            fn parseChunkHeader(self: *PngChunk) !void {
                self.len = try self.img_reader.readIntBig(u32);
                var chunk_t = try self.img_reader.readIntNative(u32);
                self.chunk_type = std.meta.intToEnum(magicNumbers.ChunkType, chunk_t) catch null;
                if (self.chunk_type == null) {
                    // + 4 is the crc which is skipped if chunk type is not known
                    try self.img_reader.skipBytes(self.len + 4, .{});
                    if (magicNumbers.ChunkType.isCritical(chunk_t)) {
                        return PngDecoderErr.CriticalChunkTypeNotSupported;
                    }
                    return;
                }
                self.crc_hasher.update(&@bitCast([4]u8, chunk_t));
            }

            fn parseChunkBody(self: *PngChunk, data_writer: anytype) !void {
                var i: usize = self.len;
                consoleLog("Parsing chunk body");

                while (@intCast(i64, i) - @intCast(i64, self.temp_data_hash_buff.len) >= 0) : (i -= self.temp_data_hash_buff.len) {
                    consoleLog("Case 1");
                    
                    _ = try self.img_reader.readAll(&self.temp_data_hash_buff);
                    self.crc_hasher.update(&self.temp_data_hash_buff);
                    consoleLog("CRC updated");

                    try data_writer.writeAll(&self.temp_data_hash_buff);
                    consoleLog("data written");
                } else {
                    consoleLog("Case 2");
                    _ = try self.img_reader.readAll(self.temp_data_hash_buff[0..i]);
                    
                    self.crc_hasher.update(self.temp_data_hash_buff[0..i]);
                    try data_writer.writeAll(self.temp_data_hash_buff[0..i]);
                    consoleLog("data written");
                }
                const hash = try self.img_reader.readIntBig(u32);
                if (hash != self.crc_hasher.final() and self.chunk_type != null) {
                    self.crc_hasher.crc = 0xffffffff;
                    consoleLog("ERROR: CRC error in chunk");
                    return PngDecoderErr.ChunkCrcErr;
                }
                self.crc_hasher.crc = 0xffffffff;
                consoleLog("Body chunk parsed");
            }
        };

        a: std.mem.Allocator,
        in_reader: ReaderType,
        zls_stream_buff_data_appended: usize,
        zlib_stream_decomp: ?std.compress.zlib.ZlibStream(std.io.FixedBufferStream([]u8).Reader),
        zlib_stream_comp: std.io.FixedBufferStream([]u8),
        zlib_buff_comp: std.ArrayList(u8),
        zlib_buff_comp_data_appended: usize,

        pub fn init(a: std.mem.Allocator, source: ReaderType) Self {
            return Self{
                .a = a,
                .in_reader = source,
                .zls_stream_buff_data_appended = 0,
                .zlib_stream_decomp = null,
                .zlib_buff_comp = std.ArrayList(u8).init(a),
                .zlib_stream_comp = undefined,
                .zlib_buff_comp_data_appended = 0,
            };
        }

        pub fn parse(self: *Self) !DecodedImg {
            var final_img: DecodedImg = undefined;
            try self.parsePngStreamHeaderSig();
            var chunk_parser = PngChunk.init(self.in_reader);
            while (true) {
                try chunk_parser.parseChunkHeader();

                // if (chunk_parser.chunk_type != null) std.debug.print("chunk type: {}, len: {d}, crc: .. data:... \n", .{ chunk_parser.chunk_type, chunk_parser.len });
                if (chunk_parser.chunk_type) |chunk_type| {
                    switch (chunk_type) {
                        magicNumbers.ChunkType.ihdr => {
                            var ihdr_data: [13]u8 = undefined;
                            var ihdr_data_stream = std.io.fixedBufferStream(&ihdr_data);

                            try chunk_parser.parseChunkBody(ihdr_data_stream.writer());

                            ihdr_data_stream.reset();
                            final_img.width = try ihdr_data_stream.reader().readIntBig(u32);
                            final_img.height = try ihdr_data_stream.reader().readIntBig(u32);
                            final_img.bit_depth = try ihdr_data_stream.reader().readIntBig(u8);
                            final_img.color_type = try std.meta.intToEnum(magicNumbers.ColorType, try ihdr_data_stream.reader().readIntBig(u8));
                            final_img.compression_method = try ihdr_data_stream.reader().readIntBig(u8);
                            final_img.filter_method = try ihdr_data_stream.reader().readIntBig(u8);
                            final_img.interlace_method = try ihdr_data_stream.reader().readIntBig(u8);

                            consoleLog("Checking allowed bit depths");

                            // performing checks on png validity and compatibility with this parser
                            try final_img.color_type.checkAllowedBitDepths(final_img.bit_depth);

                            consoleLog("Check color type");
                            switch (final_img.color_type) {
                                magicNumbers.ColorType.truecolor => {
                                    final_img.img_size = final_img.width * final_img.height * (final_img.bit_depth / 8) * 3;
                                },
                                magicNumbers.ColorType.truecolor_alpha => {
                                    final_img.img_size = final_img.width * final_img.height * (final_img.bit_depth / 8) * 4;
                                },
                                else => {
                                    consoleLog("ERROR: Color type not supported");
                                    return PngDecoderErr.ColorTypeNotSupported;
                                },
                            }
                            if (final_img.compression_method != 0) {
                                consoleLog("ERROR: Compression not supported");
                                return PngDecoderErr.CompressionNotSupported;
                            }   
                            if (final_img.filter_method != 0) {
                                consoleLog("ERROR: Filter non supported");
                                return PngDecoderErr.FilterNotSupported;
                            }
                            if (final_img.interlace_method != 0) {
                                consoleLog("ERRORL Interlace mode not supported");
                                return PngDecoderErr.InterlaceNotSupported;
                            }
                            consoleLog("IHDR Chunk parsed");
                        },
                        magicNumbers.ChunkType.idat => {
                            try chunk_parser.parseChunkBody(self.zlib_buff_comp.writer());
                            consoleLog("Body chunk parsed");
                        },
                        magicNumbers.ChunkType.iend => {
                            self.zlib_stream_comp = std.io.fixedBufferStream(self.zlib_buff_comp.items);
                            consoleLog("Decompressing IEND chunk");

                            self.zlib_stream_decomp = try std.compress.zlib.zlibStream(self.a, self.zlib_stream_comp.reader());
                            final_img.bitmap_reader = self.zlib_stream_decomp.?.reader();
                            consoleLog("IEND chunk parsed");

                            return final_img;
                        },
                    }
                }
            }
        }
        pub fn deinit(self: *Self) void {
            if (self.zlib_stream_decomp) |*zlib_stream_decomp|
                zlib_stream_decomp.*.deinit();
            self.zlib_buff_comp.deinit();
        }

        fn parsePngStreamHeaderSig(self: *Self) !void {
            if (!std.mem.eql(u8, &(try self.in_reader.readBytesNoEof(8)), &magicNumbers.PngStreamStart))
                return PngDecoderErr.MissingPngSig;
        }
    };
}

