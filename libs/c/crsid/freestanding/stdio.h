/* wasm32-freestanding: only the song-length parser (unreached: no SongLengths) formats text (zm_sid_libc.c). */
#pragma once
#include <stddef.h>
int sprintf(char *s, const char *fmt, ...);
int sscanf(const char *s, const char *fmt, ...);
