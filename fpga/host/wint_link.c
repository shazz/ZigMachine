/* wint's code and data sections, and the instantiation (wint.h): what wint_load.c's section
 * walk hands over, then the browser's order: imports linked (wint_load.c), every active data
 * segment checked against the memory before any is written, the start function run. */
#include <string.h>

#include "wint.h"
#include "wint_leb.h"

#define FAIL(st, msg) do { w->why = (msg); return (st); } while (0)
#define U32(v) do { if (wint_u32(w->m, end, pc, (v))) FAIL(WINT_E_FORMAT, "truncated number"); } while (0)

wint_status wint_parse(wint* w);

static wint_status body(wint* w, wint_func* f, uint32_t end, uint32_t* pc) {
    uint32_t groups, n, total = 0;
    uint8_t vt;
    U32(&groups);
    for (uint32_t g = 0; g < groups; g++) {
        U32(&n);
        if (wint_byte(w->m, end, pc, &vt)) FAIL(WINT_E_FORMAT, "local type");
        if (n > WINT_STACK - total) FAIL(WINT_E_UNSUPPORTED, "too many locals");
        total += n;
    }
    f->nlocals = (uint16_t)total;
    f->body = (uint16_t)*pc;
    f->end = (uint16_t)end;
    wint_status st = wint_scan(w, *pc, end, total + w->types[f->type].np);
    *pc = end;
    return st;
}

wint_status wint_sections_code(wint* w, uint32_t end, uint32_t* pc) {
    uint32_t n, size, first = 0;
    while (first < w->nfuncs && w->funcs[first].imported) first++;
    U32(&n);
    if (n != w->nfuncs - first) FAIL(WINT_E_FORMAT, "code and function counts differ");
    for (uint32_t i = 0; i < n; i++) {
        U32(&size);
        if (size > end - *pc) FAIL(WINT_E_FORMAT, "body past its section");
        wint_status st = body(w, &w->funcs[first + i], *pc + size, pc);
        if (st) return st;
    }
    return WINT_OK;
}

/* Active segments (flags 0, or 2 with memory 0) are kept to write at instantiation; a passive
 * one (flags 1) only matters to memory.init, which wint refuses: it is skipped. */
wint_status wint_sections_data(wint* w, uint32_t end, uint32_t* pc) {
    uint32_t n, flags, memidx = 0, len;
    U32(&n);
    for (uint32_t i = 0; i < n; i++) {
        uint64_t at = 0;
        uint8_t op, e;
        U32(&flags);
        if (flags > 2) FAIL(WINT_E_FORMAT, "data flags");
        if (flags == 2) U32(&memidx);
        if (memidx != 0) FAIL(WINT_E_UNSUPPORTED, "a second memory");
        if (flags != 1) {
            if (wint_byte(w->m, end, pc, &op) || op != 0x41) FAIL(WINT_E_UNSUPPORTED, "a data offset that is not i32.const");
            if (wint_leb(w->m, end, pc, 32, 1, &at) || wint_byte(w->m, end, pc, &e) || e != 0x0B)
                FAIL(WINT_E_FORMAT, "data offset");
        }
        U32(&len);
        if (len > end - *pc) FAIL(WINT_E_FORMAT, "data past its section");
        if (flags != 1) {
            if (w->ndata >= WINT_MAX_DATA) FAIL(WINT_E_UNSUPPORTED, "too many data segments");
            w->data[w->ndata++] = (wint_data){(uint32_t)at, *pc, len};
        }
        *pc += len;
    }
    return WINT_OK;
}

/* Every defined function has a body, and nothing past the sections dangles. */
static wint_status complete(wint* w) {
    for (uint32_t i = 0; i < w->nfuncs; i++)
        if (!w->funcs[i].imported && w->funcs[i].end == 0) FAIL(WINT_E_FORMAT, "a function without a body");
    for (uint32_t i = 0; i < w->ndata; i++)
        if ((uint64_t)w->data[i].at + w->data[i].len > w->mem_len) FAIL(WINT_E_LINK, "a data segment past the memory");
    return WINT_OK;
}

wint_status wint_load(wint* w, const uint8_t* m, uint32_t len, uint8_t* mem, uint32_t mem_len,
                      const wint_import* host, int nhost, void* ctx) {
    memset(w, 0, sizeof *w);
    w->m = m, w->len = len, w->mem = mem, w->mem_len = mem_len, w->host = host, w->nhost = nhost, w->ctx = ctx;
    w->start = WINT_NO_FUNC;
    if (len > WINT_MAX_BYTES) FAIL(WINT_E_UNSUPPORTED, "larger than a boot sector");
    wint_status st = wint_parse(w);
    if (st || (st = complete(w))) return st;
    for (uint32_t i = 0; i < w->ndata; i++) memcpy(mem + w->data[i].at, m + w->data[i].from, w->data[i].len);
    if (w->start == WINT_NO_FUNC) return WINT_OK;
    uint64_t r;
    return wint_call(w, w->start, NULL, 0, &r, 1u << 24);
}

int wint_export_func(const wint* w, const char* name) {
    size_t n = strlen(name);
    for (uint32_t i = 0; i < w->nexports; i++)
        if (w->exports[i].name_len == n && memcmp(w->m + w->exports[i].name, name, n) == 0) return w->exports[i].func;
    return -1;
}
