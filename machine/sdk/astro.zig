// --------------------------------------------------------------------------
// ASTROLABE (ASTRO) — the f64 coprocessor's ABI (HW 1.18.0, SPIKE: docs/ARM_FPU_COPROC.md)
//
// The Mega ST's SFP004 put a 68881 beside the 68000, driven through a few memory-mapped
// registers. ASTROLABE is the same idea for KESTREL: the cart describes work in
// DESCRIPTORS in its own memory and calls env.hwAstro(desc, count); the machine runs them
// in order and writes each one's status (and scalar result) back into it.
//   - the browser and the native host: the machine itself computes (machine/astro.zig);
//   - the board: the firmware hands them to the ARM Cortex-A9's VFPv3 through a 4 KB
//     BRAM mailbox (fpga/cycles/bastro.c -> fpga/glass/src/astro.zig), and computes
//     them itself (the same machine code, soft f64 on ZIGGY) when nobody answers.
// Every host runs the SAME kernels (machine/astro_ops.zig), so even libm results agree.
//
// Pure constants: imported by the machine, the SDK, glass and the tests.
// --------------------------------------------------------------------------

// --- the descriptor: DESC_WORDS little-endian u32 words, 8-byte aligned -------------
pub const DESC_WORDS: u32 = 20;
pub const DESC_BYTES: u32 = DESC_WORDS * 4; // 80
pub const W_OP: u32 = 0; // op (low 16 bits) | TYPE_* flags (high 16)
pub const W_N: u32 = 1; // elements (vector), columns (gemv), order (gefa/gesl)
pub const W_M: u32 = 2; // rows (gemv); MAP: the function (FN_*)
pub const W_LDA: u32 = 3; // leading dimension, in elements (gemv, gefa, gesl)
pub const W_A: u32 = 4; // cart address of array A
pub const W_B: u32 = 5; // cart address of array B (gefa/gesl: the pivots, i32)
pub const W_C: u32 = 6; // cart address of array C (the destination; gesl: the right-hand side)
pub const W_RSVD: u32 = 7; // 0
pub const W_STATUS: u32 = 8; // written: ST_* code | SERVED_ARM
pub const W_CYCLES: u32 = 9; // written: ZIGGY cycles the call took on the board (0 elsewhere)
pub const W_S0: u32 = 10; // f64 scalar operand 0 (alpha for AXPY / SCAL)
pub const W_S1: u32 = 12; // f64 scalar operand 1
pub const W_S2: u32 = 14; // f64 scalar operand 2 (FMA's addend)
pub const W_R: u32 = 16; // f64 scalar result (DOT, scalar ops; GEFA: info = first zero pivot + 1, 0 = none)
pub const W_PAD: u32 = 18; // 2 words, 0

// --- TYPE flags (W_OP high half): the element type of the arrays ----------------------
// The arithmetic is always f64; an f32 array is widened on load and rounded on store.
pub const TYPE_F32_IN: u32 = 1 << 16; // A and B hold f32
pub const TYPE_F32_OUT: u32 = 1 << 17; // C holds f32
pub const TYPE_F32: u32 = TYPE_F32_IN | TYPE_F32_OUT;
pub const TYPE_MASK: u32 = TYPE_F32;
pub const OP_MASK: u32 = 0xFFFF;

// --- ops ------------------------------------------------------------------------------
pub const OP_NOP: u32 = 0x00; // nothing: the round trip alone
// scalar: R = f(S0, S1, S2)
pub const OP_ADD: u32 = 0x01;
pub const OP_SUB: u32 = 0x02;
pub const OP_MUL: u32 = 0x03;
pub const OP_DIV: u32 = 0x04;
pub const OP_SQRT: u32 = 0x05;
pub const OP_FMA: u32 = 0x06; // S0 * S1 + S2, rounded once
pub const OP_SIN: u32 = 0x10;
pub const OP_COS: u32 = 0x11;
pub const OP_TAN: u32 = 0x12;
pub const OP_ATAN2: u32 = 0x13; // atan2(S0 = y, S1 = x)
pub const OP_EXP: u32 = 0x14;
pub const OP_LOG: u32 = 0x15;
pub const OP_POW: u32 = 0x16; // S0 ^ S1
// vector, N elements: A, B in; C out (or B in place)
pub const OP_VADD: u32 = 0x20; // C = A + B
pub const OP_VMUL: u32 = 0x21; // C = A * B
pub const OP_AXPY: u32 = 0x22; // B = S0 * A + B (BLAS daxpy)
pub const OP_DOT: u32 = 0x23; // R = A . B, accumulated in f64
pub const OP_SCAL: u32 = 0x24; // C = S0 * A
pub const OP_MAP: u32 = 0x25; // C = FN(A), FN in W_M
// matrix (column-major, LINPACK's layout)
pub const OP_GEMV: u32 = 0x30; // C[M] = A[M x N, lda] * B[N]
pub const OP_GEFA: u32 = 0x31; // LINPACK dgefa: A[N x N, lda] factored in place, pivots into B (i32); R = info
pub const OP_GESL: u32 = 0x32; // LINPACK dgesl (job 0): solves A x = C in place with A, B from GEFA

// MAP's functions (W_M)
pub const FN_SIN: u32 = 0;
pub const FN_COS: u32 = 1;
pub const FN_TAN: u32 = 2;
pub const FN_EXP: u32 = 3;
pub const FN_LOG: u32 = 4;
pub const FN_SQRT: u32 = 5;
pub const FN_ATAN: u32 = 6;
pub const FN_COUNT: u32 = 7;

// --- status (W_STATUS low byte); hwAstro returns the first non-OK one, else OK ---------
pub const ST_OK: u32 = 0;
pub const ST_BAD_OP: u32 = 1; // an op or a MAP function this machine does not know
pub const ST_RANGE: u32 = 2; // an array outside the memory, or a count past the limits
pub const ST_ALIGN: u32 = 3; // an array not aligned to its element (4 for f32/i32, 8 for f64)
pub const ST_BAD_DESC: u32 = 4; // the descriptor itself outside the memory or not 8-aligned
pub const ST_TIMEOUT: u32 = 5; // board only: the ARM took the request and did not finish it in time
// Bit 8: the ARM served it (board only). 0 = the machine's own code did (browser, native host,
// or the board's fallback when the mailbox is absent or did not answer in time).
pub const SERVED_ARM: u32 = 1 << 8;

// --- limits ---------------------------------------------------------------------------
pub const MAX_COUNT: u32 = 48; // descriptors a call (the board's mailbox holds 48)
pub const MAX_N: u32 = 1 << 20; // elements of a vector op
pub const MAX_ORDER: u32 = 1024; // N and M of a matrix op
