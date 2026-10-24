/* wint's loader (wint.h): the module's sections, checked as they are read, then the browser's
 * instantiation (WebAssembly.instantiate with the loader's env): imports linked, active data
 * segments written into the memory, the start function run. */
#include <string.h>

#include "wint.h"
#include "wint_leb.h"

#define FAIL(st, msg) do { w->why = (msg); return (st); } while (0)
#define U32(v) do { if (wint_u32(w->m, end, pc, (v))) FAIL(WINT_E_FORMAT, "truncated number"); } while (0)

static int name_is(const wint* w, uint32_t at, uint32_t n, const char* s) {
    return strlen(s) == n && memcmp(w->m + at, s, n) == 0;
}

static wint_status name(wint* w, uint32_t end, uint32_t* pc, uint32_t* at, uint32_t* n) {
    U32(n);
    if (*n > end - *pc) FAIL(WINT_E_FORMAT, "name past its section");
    *at = *pc;
    *pc += *n;
    return WINT_OK;
}

static wint_status types(wint* w, uint32_t end, uint32_t* pc) {
    uint32_t n, np, nr;
    U32(&n);
    if (n > WINT_MAX_TYPES) FAIL(WINT_E_UNSUPPORTED, "too many types");
    for (w->ntypes = 0; w->ntypes < n; w->ntypes++) {
        uint8_t form;
        if (wint_byte(w->m, end, pc, &form) || form != 0x60) FAIL(WINT_E_FORMAT, "not a function type");
        U32(&np);
        if (np > WINT_MAX_ARGS || np > end - *pc) FAIL(WINT_E_UNSUPPORTED, "too many params");
        *pc += np;
        U32(&nr);
        if (nr > WINT_MAX_ARGS || nr > end - *pc) FAIL(WINT_E_UNSUPPORTED, "too many results");
        *pc += nr;
        w->types[w->ntypes] = (wint_type){.np = (uint8_t)np, .nr = (uint8_t)nr};
    }
    return WINT_OK;
}

static wint_status memory_import(wint* w, uint32_t end, uint32_t* pc) {
    uint8_t flags;
    uint32_t min, max = 0, pages = w->mem_len / WINT_PAGE;
    if (wint_byte(w->m, end, pc, &flags) || flags > 1) FAIL(WINT_E_UNSUPPORTED, "memory limits");
    U32(&min);
    if (flags) U32(&max);
    if (min > pages || (flags && max < pages)) FAIL(WINT_E_LINK, "the memory's size does not match the import");
    return WINT_OK;
}

static wint_status import_func(wint* w, uint32_t end, uint32_t* pc, uint32_t at, uint32_t n) {
    uint32_t t;
    U32(&t);
    if (t >= w->ntypes) FAIL(WINT_E_FORMAT, "import type");
    if (w->nfuncs >= WINT_MAX_FUNCS) FAIL(WINT_E_UNSUPPORTED, "too many functions");
    if (w->types[t].nr > 1) FAIL(WINT_E_UNSUPPORTED, "an import with several results");
    wint_func* f = &w->funcs[w->nfuncs++];
    *f = (wint_func){.type = (uint16_t)t, .imported = 1};
    for (int i = 0; i < w->nhost; i++)
        if (name_is(w, at, n, w->host[i].name)) f->host = w->host[i].fn;
    return WINT_OK;
}

static wint_status imports(wint* w, uint32_t end, uint32_t* pc) {
    uint32_t n, mat, mn, at, len;
    uint8_t kind;
    wint_status st;
    U32(&n);
    for (uint32_t i = 0; i < n; i++) {
        if ((st = name(w, end, pc, &mat, &mn)) || (st = name(w, end, pc, &at, &len))) return st;
        if (!name_is(w, mat, mn, "env")) FAIL(WINT_E_LINK, "an import from a module other than env");
        if (wint_byte(w->m, end, pc, &kind)) FAIL(WINT_E_FORMAT, "import kind");
        if (kind == 0) st = import_func(w, end, pc, at, len);
        else if (kind == 2 && name_is(w, at, len, "memory")) st = memory_import(w, end, pc);
        else FAIL(WINT_E_UNSUPPORTED, "an import that is not a function or env.memory");
        if (st) return st;
    }
    return WINT_OK;
}

static wint_status functions(wint* w, uint32_t end, uint32_t* pc) {
    uint32_t n, t;
    U32(&n);
    if (n > WINT_MAX_FUNCS - w->nfuncs) FAIL(WINT_E_UNSUPPORTED, "too many functions");
    for (uint32_t i = 0; i < n; i++) {
        U32(&t);
        if (t >= w->ntypes) FAIL(WINT_E_FORMAT, "function type");
        w->funcs[w->nfuncs++] = (wint_func){.type = (uint16_t)t};
    }
    return WINT_OK;
}

/* A constant expression: one *.const, then end. f32/f64 are kept as their bits. */
static wint_status const_expr(wint* w, uint32_t end, uint32_t* pc, uint64_t* v) {
    uint8_t op, e;
    if (wint_byte(w->m, end, pc, &op)) FAIL(WINT_E_FORMAT, "constant");
    if (op == 0x41 || op == 0x42) {
        if (wint_leb(w->m, end, pc, op == 0x41 ? 32 : 64, 1, v)) FAIL(WINT_E_FORMAT, "constant");
        if (op == 0x41) *v = (uint32_t)*v;
    } else if (op == 0x43 || op == 0x44) {
        uint32_t k = op == 0x43 ? 4 : 8;
        if (k > end - *pc) FAIL(WINT_E_FORMAT, "constant");
        *v = 0;
        for (uint32_t i = 0; i < k; i++) *v |= (uint64_t)w->m[*pc + i] << (8 * i);
        *pc += k;
    } else {
        FAIL(WINT_E_UNSUPPORTED, "a constant expression that is not a *.const");
    }
    if (wint_byte(w->m, end, pc, &e) || e != 0x0B) FAIL(WINT_E_FORMAT, "constant's end");
    return WINT_OK;
}

static wint_status globals(wint* w, uint32_t end, uint32_t* pc) {
    uint32_t n;
    uint8_t vt, mut;
    wint_status st;
    U32(&n);
    if (n > WINT_MAX_GLOBALS) FAIL(WINT_E_UNSUPPORTED, "too many globals");
    for (w->nglobals = 0; w->nglobals < n; w->nglobals++) {
        if (wint_byte(w->m, end, pc, &vt) || wint_byte(w->m, end, pc, &mut)) FAIL(WINT_E_FORMAT, "global");
        w->gmut[w->nglobals] = mut;
        if ((st = const_expr(w, end, pc, &w->globals[w->nglobals]))) return st;
    }
    return WINT_OK;
}

static wint_status exports(wint* w, uint32_t end, uint32_t* pc) {
    uint32_t n, at, len, idx;
    uint8_t kind;
    wint_status st;
    U32(&n);
    for (uint32_t i = 0; i < n; i++) {
        if ((st = name(w, end, pc, &at, &len))) return st;
        if (wint_byte(w->m, end, pc, &kind)) FAIL(WINT_E_FORMAT, "export kind");
        U32(&idx);
        if (kind != 0) continue; /* a table, memory or global export: nothing calls it */
        if (idx >= w->nfuncs) FAIL(WINT_E_FORMAT, "export index");
        if (w->nexports >= WINT_MAX_EXPORTS) FAIL(WINT_E_UNSUPPORTED, "too many exports");
        w->exports[w->nexports++] = (wint_export){(uint16_t)at, (uint16_t)len, (uint16_t)idx};
    }
    return WINT_OK;
}

wint_status wint_sections_code(wint* w, uint32_t end, uint32_t* pc);
wint_status wint_sections_data(wint* w, uint32_t end, uint32_t* pc);

static wint_status section(wint* w, uint8_t id, uint32_t end, uint32_t* pc) {
    switch (id) {
    case 1: return types(w, end, pc);
    case 2: return imports(w, end, pc);
    case 3: return functions(w, end, pc);
    case 5: FAIL(WINT_E_UNSUPPORTED, "a memory of its own (a boot sector draws in env.memory)");
    case 6: return globals(w, end, pc);
    case 7: return exports(w, end, pc);
    case 8: { uint32_t s; U32(&s); if (s >= w->nfuncs) FAIL(WINT_E_FORMAT, "start"); w->start = (uint16_t)s; return WINT_OK; }
    case 10: return wint_sections_code(w, end, pc);
    case 11: return wint_sections_data(w, end, pc);
    default: *pc = end; return WINT_OK; /* custom, table, element, data count: nothing to run */
    }
}

wint_status wint_parse(wint* w) {
    uint32_t pc = 8, size;
    static const uint8_t magic[8] = {0, 'a', 's', 'm', 1, 0, 0, 0};
    if (w->len < 8 || memcmp(w->m, magic, 8) != 0) FAIL(WINT_E_FORMAT, "no wasm header");
    while (pc < w->len) {
        uint8_t id = w->m[pc++];
        if (wint_u32(w->m, w->len, &pc, &size) || size > w->len - pc) FAIL(WINT_E_FORMAT, "section size");
        uint32_t end = pc + size;
        wint_status st = section(w, id, end, &pc);
        if (st) return st;
        if (pc != end) FAIL(WINT_E_FORMAT, "a section's size does not match its contents");
    }
    return WINT_OK;
}
