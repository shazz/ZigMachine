# KESTREL (v1): no C++ exceptions on the cart. A throw logs its message and stops the cart; try/catch become plain
# blocks. A valid project loads as before; a malformed one stops the cart instead of showing an error.
s/throw \([A-Za-z_][A-Za-z0-9_]*\);/kestrel_throw(\1);/g
s/throw \("[^"]*"\);/kestrel_throw(\1);/g
s/^\(\s*\)try {/\1{ \/* KESTREL: was try *\//
s/} catch (const char\* error) {/} if (0) { const char* error = "";/
