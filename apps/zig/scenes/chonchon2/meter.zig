// --------------------------------------------------------------------------
// The three music meters -- internal/demo/game.go's Update, transcribed.
//
// For each channel, volume = YM register 8+channel & 15. Every meter row is
// seven scanlines high, and cells 0..volume are filled; one cell is 16 pixels
// wide and its word is 0x0000ffff (planes 2 and 3, i.e. index 12).
//
//   channel 0: rows 167..173, x = 16 + cell*16
//   channel 1: rows 176..182, same x
//   channel 2: rows 185..191, same x
//
// 0x6868 = 167*160 + 8 is the first channel's first cell's word; each channel
// is 0x5a0 (nine 160-byte rows) apart, each row 160 bytes, each cell 8 bytes.
// --------------------------------------------------------------------------
pub fn apply(screen: []u8, regs: [14]u8) void {
    var channel: usize = 0;
    while (channel < 3) : (channel += 1) {
        const volume = regs[8 + channel] & 15;
        var row: usize = 0;
        while (row < 7) : (row += 1) {
            var cell: usize = 0;
            while (cell <= volume) : (cell += 1) {
                const off = 0x6868 + channel * 0x5a0 + row * 160 + cell * 8;
                if (off + 4 > screen.len) continue;
                screen[off] = 0;
                screen[off + 1] = 0;
                screen[off + 2] = 0xff;
                screen[off + 3] = 0xff;
            }
        }
    }
}
