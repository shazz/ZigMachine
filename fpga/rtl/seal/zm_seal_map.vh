// The cart CPU's bus windows: what U-mode (cart and ROM code) may touch.
// THE map: rtl/seal/zm_seal.v decides from it, tests/test_rtl_seal.py hands it to
// the testbenches as -D's, and the firmware's linker script must place its
// sections in these windows (rtl/seal/README.md). Every window is a power of two
// in size and aligned to it, so a hit is a compare of the address's top bits.
//
// Cart CPU bus addresses. main_ram (the 32 MiB cart window of DDR) starts at
// 0x4000_0000; everything outside the windows below, i.e. the firmware's 8 MiB,
// the boot ROM/SRAM, the CSR bus (UART, the video `cmd`/`mem_base`, the glass)
// and any other DDR, is M-only.
`ifndef ZM_SEAL_MAP_VH
`define ZM_SEAL_MAP_VH

`define ZS_FW_BASE      32'h4000_0000  // 8 MiB  firmware, M-only (listed for the tests)
`define ZS_FW_LOG2      23
`define ZS_CODE_BASE    32'h4080_0000  // 8 MiB  U: --X  cart + ROM text and what they call: execute-only
`define ZS_CODE_LOG2    23
`define ZS_RODATA_BASE  32'h4100_0000  // 4 MiB  U: R--  their constants (.rodata, jump tables)
`define ZS_RODATA_LOG2  22
`define ZS_DATA_BASE    32'h4140_0000  // 4 MiB  U: RW-  their instance data, globals, U stack
`define ZS_DATA_LOG2    22
`define ZS_LINEAR_BASE  32'h4180_0000  // 8 MiB  U: RW-  the machine's 7 MiB shared wasm memory
`define ZS_LINEAR_LOG2  23
`define ZS_VIDEO_BASE   32'h9000_0000  // 8 MiB  U: RW-  the compositor's register window
`define ZS_VIDEO_LOG2   23

`endif
