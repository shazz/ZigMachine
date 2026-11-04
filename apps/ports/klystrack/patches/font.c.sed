# KESTREL: a string is drawn as one group (kestrel_port.h): when the same string (font, rectangle, cursor and
# bounds going in, the bytes; the same texture and renderer state) was drawn at this point last frame, its glyph
# copies are reused and the cursor/bounds it left are handed back, instead of a findchar + blit a glyph.
# inner_write draws the font's surface only and writes *cursor / *bounds: those are the group's outputs.
s/^static void inner_write(const Font \*font, GfxDomain \*dest, const SDL_Rect \*r, Uint16 \* cursor, SDL_Rect \*bounds, const char \* text)$/static void inner_write_draw(const Font *font, GfxDomain *dest, const SDL_Rect *r, Uint16 * cursor, SDL_Rect *bounds, const char * text)/
/^void font_write_va(const Font \*font, GfxDomain \*dest, const SDL_Rect \*r, Uint16 \* cursor, SDL_Rect \*bounds, const char \* text, va_list va)$/i\
#define KESTREL_TEXT_MAX 180 /* bytes; a longer string is drawn as before */\
static void inner_write(const Font *font, GfxDomain *dest, const SDL_Rect *r, Uint16 * cursor, SDL_Rect *bounds, const char * text)\
{\
	unsigned key[9 + KESTREL_TEXT_MAX / 4] = { 0 }, out[3], len = (unsigned)strlen(text);\
	if (len > KESTREL_TEXT_MAX || !font->surface) { inner_write_draw(font, dest, r, cursor, bounds, text); return; }\
	key[0] = (unsigned)(uintptr_t)font; key[1] = (r != NULL) | (bounds != NULL) << 1; key[2] = *cursor; key[3] = (unsigned)dest->screen_w; key[4] = len;\
	if (r) { key[5] = (unsigned)(Uint16)r->x | (unsigned)r->y << 16; key[6] = (unsigned)(Uint16)r->w | (unsigned)r->h << 16; }\
	if (bounds) { key[7] = (unsigned)(Uint16)bounds->x | (unsigned)bounds->y << 16; key[8] = (unsigned)(Uint16)bounds->w | (unsigned)bounds->h << 16; }\
	memcpy(key + 9, text, len);\
	if (kestrel_group_begin(dest->renderer, font->surface->texture, key, 9 + (len + 3) / 4, out, 3))\
	{\
		*cursor = (Uint16)out[0];\
		if (bounds) { bounds->x = (Sint16)(Uint16)out[1]; bounds->y = (int)out[1] >> 16; bounds->w = (Sint16)(Uint16)out[2]; bounds->h = (int)out[2] >> 16; }\
		return;\
	}\
	inner_write_draw(font, dest, r, cursor, bounds, text);\
	out[0] = *cursor; out[1] = bounds ? ((unsigned)(Uint16)bounds->x | (unsigned)bounds->y << 16) : 0; out[2] = bounds ? ((unsigned)(Uint16)bounds->w | (unsigned)bounds->h << 16) : 0;\
	kestrel_group_end(out, 3);\
}\

# ...a space (no glyph) keeps a place in the window's list, so a string's draws are as many as its bytes and a
# change of letters does not move every later draw to another position;
s/^\t\t\tx += font->space_width;$/\t\t\tx += font->space_width; kestrel_window_nop(dest->renderer);/
# ...and the label is formatted by kestrel_printf.c (musl's output; the common conversions without its FILE layer).
s/^\tvsnprintf(formatted, len, text, va);$/\tkestrel_vsnprintf(formatted, len, text, va);/
