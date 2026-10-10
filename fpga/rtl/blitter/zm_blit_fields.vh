// The register fields, decoded from the flat word vector `rf` (see zm_blit_regs.v).
// Included inside a module that has `rf`. 16-bit fields are the low/high half of a word.
wire [7:0]   f_cmd = rf[7:0],    f_mt = rf[15:8],   f_con = rf[23:16];
wire [7:0]   f_color = rf[39:32], f_bg = rf[47:40], f_key = rf[55:48], f_con2 = rf[63:56];
wire [31:0]  f_a_base = rf[95:64],   f_b_base = rf[159:128], f_d_base = rf[287:256];
wire [15:0]  f_a_stride = rf[111:96], f_b_stride = rf[175:160], f_d_stride = rf[303:288];
wire [15:0]  f_w = rf[335:320],  f_h = rf[351:336];
wire [15:0]  f_x0 = rf[367:352], f_y0 = rf[383:368], f_x1 = rf[399:384];
wire [15:0]  f_y1 = rf[415:400], f_x2 = rf[431:416], f_y2 = rf[447:432];
wire [15:0]  f_clip_x = rf[463:448], f_clip_y = rf[479:464], f_clip_w = rf[495:480], f_clip_h = rf[511:496];
wire [255:0] f_ht = rf[767:512];  // 16 rows of 16 bits: bit [y*16 + x]
