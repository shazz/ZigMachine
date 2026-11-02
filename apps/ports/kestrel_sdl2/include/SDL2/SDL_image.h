/* SDL_image shim. By default no image codecs on the cart: IMG_Load fails, so callers fall back to their own
 * loaders (GrafX2). A port that defines KESTREL_SDL_IMAGE links src/opt/kestrel_image.c instead: PNG (and the
 * other stb_image formats) through stb_image, decoded to ARGB8888 surfaces. */
#ifndef KESTREL_SDL_IMAGE_H
#define KESTREL_SDL_IMAGE_H
#include "SDL.h"
#define SDL_IMAGE_MAJOR_VERSION 2
#define SDL_IMAGE_MINOR_VERSION 0
#define SDL_IMAGE_PATCHLEVEL 0
#ifdef KESTREL_SDL_IMAGE
SDL_Surface *IMG_Load(const char *file);
SDL_Surface *IMG_Load_RW(SDL_RWops *src, int freesrc);
const SDL_version *IMG_Linked_Version(void);
#else
static inline SDL_Surface *IMG_Load(const char *file) { (void)file; return NULL; }
static inline const SDL_version *IMG_Linked_Version(void) { static const SDL_version v = { 2, 0, 0 }; return &v; }
#endif
#endif
