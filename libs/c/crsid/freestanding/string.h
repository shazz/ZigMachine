/* wasm32-freestanding: what cRSID's non-PC build includes and calls (zm_sid_libc.c). */
#pragma once
#include <stddef.h>
void *memset(void *d, int c, size_t n);
void *memcpy(void *d, const void *s, size_t n);
size_t strlen(const char *s);
char *strchr(const char *s, int c);
int strncmp(const char *a, const char *b, size_t n);
size_t strcspn(const char *s, const char *reject);
size_t strspn(const char *s, const char *accept);
char *strncpy(char *d, const char *s, size_t n);
