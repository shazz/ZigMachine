"""The fixed half of the KESTREL system table's layout (tools/sys_abi.py adds the env
entries from the modules). Any change here changes the layout, so sys_abi.py --check fails
until --update bumps the major version: rebuild every cart then.

RUNTIME: what a lean cart takes from the system instead of linking it (decisions.md
2026-10-15): the wasm2c runtime's shared state (the trap's jmp_buf, the heap the funcref
tables are calloc'd from), libc/libm (whose errno lives in the system's TLS), and the two
host hooks env.c served (hostMicros, the drive). Rows: (symbol, return, params, the cart
defines a forwarder by that name). The table's first entries, in this order.
"""

NORETURN = ("wasm_rt_trap", "__assert_func")

RUNTIME = [
    ("w2c_env_memory", "wasm_rt_memory_t*", ["struct w2c_env*"], True),
    ("wasm_rt_trap", "void", ["wasm_rt_trap_t"], True),
    ("wasm_rt_is_initialized", "bool", [], True),
    ("wasm_rt_allocate_funcref_table", "void", ["wasm_rt_funcref_table_t*", "uint32_t", "uint32_t"], True),
    ("wasm_rt_free_funcref_table", "void", ["wasm_rt_funcref_table_t*"], True),
    ("__assert_func", "void", ["const char*", "int", "const char*", "const char*"], True),
    ("memcpy", "void*", ["void*", "const void*", "size_t"], True),
    ("memmove", "void*", ["void*", "const void*", "size_t"], True),
    ("memset", "void*", ["void*", "int", "size_t"], True),
    ("memcmp", "int", ["const void*", "const void*", "size_t"], True),
    *[
        (f + s, t, [t], True)
        for f in ("floor", "ceil", "trunc", "nearbyint", "sqrt", "fabs")
        for s, t in (("", "double"), ("f", "float"))
    ],  # fmt: skip
    ("host_to_i32", "uint32_t", ["double"], True),  # the --call table's ToInt32 (host/boot.c)
    ("zm_host_micros", "uint32_t", [], False),
    ("zm_disk_read", "uint32_t", ["struct w2c_env*", "uint32_t", "uint32_t"], False),
]

# The structs the header points at, read from the sources both images compile (sys_abi.py
# c_types), and the table itself, which the generated header defines.
TYPE_SOURCES = [
    ("host/host.h", ["host_export", "host_song_bridge", "host_input_bridge", "host_disk_app_bridge"]),
    ("cycles/baudio.h", ["zm_song"]),
]
TYPES = [("zm_sys_table", "{uint32_t magic; uint32_t version; uint32_t count; zm_fn fn[ZM_SYS_COUNT];}")]

# The cart header (zm_cart_hdr), at offset 0 of the cart image: (field, C declarator with {}
# for the name). glass reads magic, version and bss_end (map_cart.zig CART_HDR_*_AT).
HEADER = [
    ("magic", "uint32_t {}"),
    ("version", "uint32_t {}"),
    ("hdr_bytes", "uint32_t {}"),
    ("bss_start", "char* {}"),
    ("bss_end", "char* {}"),
    ("pages", "uint32_t {}"),
    ("cart_high", "uint32_t {}"),
    ("inst_bytes", "uint32_t {}"),
    ("bind", "void (*{})(const struct zm_sys_table*)"),
    ("instantiate", "void (*{})(struct w2c_cart*, struct w2c_env*)"),
    ("boot", "void (*{})(struct w2c_cart*)"),
    ("skip_boot", "void (*{})(struct w2c_cart*)"),
    ("frame", "void (*{})(struct w2c_cart*, float)"),
    ("plane_enabled", "uint32_t (*{})(struct w2c_cart*, uint32_t)"),
    ("hbl_dispatch", "void (*{})(struct w2c_cart*, uint32_t, uint32_t, uint32_t, uint32_t)"),
    ("songs", "const struct host_song_bridge* {}"),
    ("input", "const struct host_input_bridge* {}"),
    ("dapp", "const struct host_disk_app_bridge* {}"),
    ("exports", "const struct host_export* {}"),
    ("song_files", "const struct zm_song* {}"),
    ("tag", "char {}[16]"),
]

# map_cart.zig's constants both images and glass agree on.
CONSTS = ["CART_IMG_AT", "CART_HDR_MAGIC", "CART_HDR_VERSION_AT", "CART_HDR_BSS_END_AT", "SYS_MAGIC",
          "SYS_HEAD_WORDS"]  # fmt: skip
