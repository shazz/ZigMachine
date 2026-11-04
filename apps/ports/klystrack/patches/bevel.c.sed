# KESTREL: a bevel is drawn as one group (kestrel_port.h): when the same bevel (area, offset, flags, the same
# texture and renderer state) was drawn at this point last frame, its tile copies are reused, not redone.
# bevelex draws gfx only, through my_BlitSurface: a pure function of its key.
s/^void bevelex(GfxDomain \*screen, const SDL_Rect \*area, GfxSurface \*gfx, int offset, int bevel_flags)$/static void bevelex_draw(GfxDomain *screen, const SDL_Rect *area, GfxSurface *gfx, int offset, int bevel_flags)/
/^#define SIZE_MINUS_BORDER/a\
static void bevelex_draw(GfxDomain *screen, const SDL_Rect *area, GfxSurface *gfx, int offset, int bevel_flags);\
void bevelex(GfxDomain *screen, const SDL_Rect *area, GfxSurface *gfx, int offset, int bevel_flags)\
{\
	unsigned key[4] = { (unsigned)(Uint16)area->x | (unsigned)area->y << 16, (unsigned)(Uint16)area->w | (unsigned)area->h << 16, (unsigned)offset, (unsigned)bevel_flags };\
	if (kestrel_group_begin(screen->renderer, gfx->texture, key, 4, NULL, 0)) return;\
	bevelex_draw(screen, area, gfx, offset, bevel_flags);\
	kestrel_group_end(NULL, 0);\
}
