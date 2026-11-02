/* SDL_endian shim: wasm32 is little-endian. */
#ifndef KESTREL_SDL_ENDIAN_H
#define KESTREL_SDL_ENDIAN_H
#include "SDL.h"
#define SDL_LIL_ENDIAN 1234
#define SDL_BIG_ENDIAN 4321
#define SDL_BYTEORDER SDL_LIL_ENDIAN
#define SDL_Swap16(x) __builtin_bswap16(x)
#define SDL_Swap32(x) __builtin_bswap32(x)
#define SDL_Swap64(x) __builtin_bswap64(x)
#define SDL_SwapLE16(x) (x)
#define SDL_SwapLE32(x) (x)
#define SDL_SwapBE16(x) SDL_Swap16(x)
#define SDL_SwapBE32(x) SDL_Swap32(x)
#endif
