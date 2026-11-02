/* SDL_syswm shim: pt2 only touches it under _WIN32; the struct keeps non-Windows code compiling. */
#ifndef KESTREL_SDL_SYSWM_H
#define KESTREL_SDL_SYSWM_H
#include "SDL.h"
typedef enum { SDL_SYSWM_UNKNOWN, SDL_SYSWM_WINDOWS } SDL_SYSWM_TYPE;
typedef struct SDL_SysWMinfo { SDL_version version; SDL_SYSWM_TYPE subsystem; } SDL_SysWMinfo;
SDL_bool SDL_GetWindowWMInfo(SDL_Window *w, SDL_SysWMinfo *info);
#endif
