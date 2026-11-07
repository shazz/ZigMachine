/* wasm32-freestanding: cRSID includes it; its non-PC build uses only abs (the VU meter). */
#pragma once
#include <stddef.h>
static inline int abs(int x) { return x < 0 ? -x : x; }
