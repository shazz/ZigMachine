# KESTREL: "struct menu_t { ... } menu_t;" also defines an unused variable menu_t in every file that includes it
# (fine with -fcommon, which wasm32 clang does not support).
s/^} menu_t;$/};/
