/* SDL_RWops on the cart: stdio files (through kestrel_wasi.c, i.e. the floppy, read-only) and memory blocks.
 * Opt-in (src/opt): a port links it by listing it in its Makefile. Read/write return object counts, as SDL 2. */
#include <SDL2/SDL.h>

SDL_RWops *SDL_AllocRW(void)
{
    SDL_RWops *rw = calloc(1, sizeof *rw);
    return rw;
}
void SDL_FreeRW(SDL_RWops *rw) { free(rw); }

Sint64 SDL_RWsize(SDL_RWops *c) { return c->size ? c->size(c) : -1; }
Sint64 SDL_RWseek(SDL_RWops *c, Sint64 off, int whence) { return c->seek ? c->seek(c, off, whence) : -1; }
Sint64 SDL_RWtell(SDL_RWops *c) { return SDL_RWseek(c, 0, RW_SEEK_CUR); }
size_t SDL_RWread(SDL_RWops *c, void *p, size_t size, size_t n) { return c->read ? c->read(c, p, size, n) : 0; }
size_t SDL_RWwrite(SDL_RWops *c, const void *p, size_t size, size_t n) { return c->write ? c->write(c, p, size, n) : 0; }
int SDL_RWclose(SDL_RWops *c) { return c->close ? c->close(c) : (SDL_FreeRW(c), 0); }

/* --- stdio --- */
static Sint64 fp_size(SDL_RWops *c)
{
    FILE *f = c->hidden.stdio.fp;
    long at = ftell(f);
    if (at < 0 || fseek(f, 0, SEEK_END) != 0) return -1;
    long end = ftell(f);
    fseek(f, at, SEEK_SET);
    return end;
}
static Sint64 fp_seek(SDL_RWops *c, Sint64 off, int whence)
{
    static const int w[3] = { SEEK_SET, SEEK_CUR, SEEK_END };
    if (whence < 0 || whence > 2) return -1;
    if (fseek(c->hidden.stdio.fp, (long)off, w[whence]) != 0) return -1;
    return ftell(c->hidden.stdio.fp);
}
static size_t fp_read(SDL_RWops *c, void *p, size_t size, size_t n) { return size && n ? fread(p, size, n, c->hidden.stdio.fp) : 0; }
static size_t fp_write(SDL_RWops *c, const void *p, size_t size, size_t n) { return size && n ? fwrite(p, size, n, c->hidden.stdio.fp) : 0; }
static int fp_close(SDL_RWops *c)
{
    int r = 0;
    if (c->hidden.stdio.autoclose) r = fclose(c->hidden.stdio.fp);
    SDL_FreeRW(c);
    return r;
}

SDL_RWops *SDL_RWFromFP(FILE *fp, SDL_bool autoclose)
{
    if (!fp) return NULL;
    SDL_RWops *c = SDL_AllocRW();
    if (!c) return NULL;
    c->size = fp_size; c->seek = fp_seek; c->read = fp_read; c->write = fp_write; c->close = fp_close;
    c->type = SDL_RWOPS_STDFILE;
    c->hidden.stdio.fp = fp;
    c->hidden.stdio.autoclose = autoclose;
    return c;
}

SDL_RWops *SDL_RWFromFile(const char *file, const char *mode)
{
    if (!file || !mode) return NULL;
    FILE *f = fopen(file, mode);
    if (!f) return NULL;
    SDL_RWops *c = SDL_RWFromFP(f, SDL_TRUE);
    if (!c) fclose(f);
    return c;
}

/* --- memory --- */
static Sint64 mem_size(SDL_RWops *c) { return c->hidden.mem.stop - c->hidden.mem.base; }
static Sint64 mem_seek(SDL_RWops *c, Sint64 off, int whence)
{
    Uint8 *base = whence == RW_SEEK_SET ? c->hidden.mem.base : whence == RW_SEEK_CUR ? c->hidden.mem.here : c->hidden.mem.stop;
    if (whence < 0 || whence > 2) return -1;
    Sint64 at = (base - c->hidden.mem.base) + off;
    if (at < 0) at = 0;
    if (at > mem_size(c)) at = mem_size(c);
    c->hidden.mem.here = c->hidden.mem.base + at;
    return at;
}
static size_t mem_read(SDL_RWops *c, void *p, size_t size, size_t n)
{
    if (!size || !n) return 0;
    size_t avail = (size_t)(c->hidden.mem.stop - c->hidden.mem.here) / size;
    if (n > avail) n = avail;
    memcpy(p, c->hidden.mem.here, n * size);
    c->hidden.mem.here += n * size;
    return n;
}
static size_t mem_write(SDL_RWops *c, const void *p, size_t size, size_t n)
{
    if (c->type == SDL_RWOPS_MEMORY_RO || !size || !n) return 0;
    size_t avail = (size_t)(c->hidden.mem.stop - c->hidden.mem.here) / size;
    if (n > avail) n = avail;
    memcpy(c->hidden.mem.here, p, n * size);
    c->hidden.mem.here += n * size;
    return n;
}
static int mem_close(SDL_RWops *c) { SDL_FreeRW(c); return 0; }

SDL_RWops *SDL_RWFromMem(void *mem, int size)
{
    if (!mem || size < 0) return NULL;
    SDL_RWops *c = SDL_AllocRW();
    if (!c) return NULL;
    c->size = mem_size; c->seek = mem_seek; c->read = mem_read; c->write = mem_write; c->close = mem_close;
    c->type = SDL_RWOPS_MEMORY;
    c->hidden.mem.base = c->hidden.mem.here = mem;
    c->hidden.mem.stop = (Uint8 *)mem + size;
    return c;
}
SDL_RWops *SDL_RWFromConstMem(const void *mem, int size)
{
    SDL_RWops *c = SDL_RWFromMem((void *)mem, size);
    if (c) c->type = SDL_RWOPS_MEMORY_RO;
    return c;
}
