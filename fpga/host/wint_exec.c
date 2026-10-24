/* wint's interpreter loop (wint.h): one switch over the opcodes wint_scan.c let through, the
 * memory accesses checked against the imported memory, a fuel unit an instruction. Blocks,
 * branches and calls are wint_flow.c's, the arithmetic wint_num.c's. */
#include <string.h>

#include "wint_exec.h"
#include "wint_leb.h"

/* Width and kind of each load 0x28..0x35 and store 0x36..0x3E: bytes | 0x10 signed | 0x20 i64. */
static const uint8_t LOADS[14] = {4, 8 | 0x20, 4, 8 | 0x20, 1 | 0x10, 1, 2 | 0x10, 2,
                                  1 | 0x30, 1 | 0x20, 2 | 0x30, 2 | 0x20, 4 | 0x30, 4 | 0x20};
static const uint8_t STORES[9] = {4, 8, 4, 8, 1, 2, 1, 2, 4};

static uint64_t rd(const uint8_t* p, uint32_t n) {
    uint32_t lo;
    if (n == 4 && !((uintptr_t)p & 3)) return memcpy(&lo, __builtin_assume_aligned(p, 4), 4), lo; /* one lw */
    uint64_t v = 0;
    for (uint32_t i = 0; i < n; i++) v |= (uint64_t)p[i] << (8 * i); /* misaligned: rv32 would trap */
    return v;
}

static void wr(uint8_t* p, uint64_t v, uint32_t n) {
    uint32_t lo = (uint32_t)v;
    if (n == 4 && !((uintptr_t)p & 3)) { memcpy(__builtin_assume_aligned(p, 4), &lo, 4); return; }
    for (uint32_t i = 0; i < n; i++) p[i] = (uint8_t)(v >> (8 * i));
}

static uint64_t extend(uint64_t v, uint8_t k) {
    uint32_t bits = 8 * (k & 0x0F);
    if ((k & 0x10) && bits < 64) v = (uint64_t)((int64_t)(v << (64 - bits)) >> (64 - bits));
    return (k & 0x20) ? v : (uint32_t)v;
}

static wint_status mem_op(wint* w, wint_ex* x, uint8_t op) {
    wint_ru32(w->m, &x->pc); /* the alignment hint */
    uint64_t off = wint_ru32(w->m, &x->pc);
    int load = op <= 0x35;
    uint32_t k = load ? LOADS[op - 0x28] : STORES[op - 0x36], n = k & 0x0F;
    WINT_NEED(x, load ? 1 : 2);
    uint64_t v = load ? 0 : w->stack[--x->sp];
    uint64_t at = (uint32_t)w->stack[--x->sp] + off;
    if (at + n > w->mem_len) return WINT_T_OOB;
    if (!load) { wr(w->mem + at, v, n); return WINT_OK; }
    w->stack[x->sp++] = extend(rd(w->mem + at, n), (uint8_t)k);
    return WINT_OK;
}

/* memory.copy (0xFC 10) and memory.fill (0xFC 11): bounds first, as wasm, then the bytes. */
static wint_status bulk(wint* w, wint_ex* x) {
    uint32_t sub = wint_ru32(w->m, &x->pc);
    x->pc += sub == 10 ? 2 : 1;
    WINT_NEED(x, 3);
    uint64_t n = (uint32_t)w->stack[x->sp - 1], s = (uint32_t)w->stack[x->sp - 2], d = (uint32_t)w->stack[x->sp - 3];
    x->sp -= 3;
    if (d + n > w->mem_len || (sub == 10 && s + n > w->mem_len)) return WINT_T_OOB;
    w->fuel = w->fuel > n / 64 ? w->fuel - (uint32_t)(n / 64) : 1; /* a big fill is not one step */
    if (sub == 10) memmove(w->mem + d, w->mem + s, (size_t)n);
    else memset(w->mem + d, (int)(uint8_t)s, (size_t)n);
    return WINT_OK;
}

static wint_status var_op(wint* w, wint_ex* x, uint8_t op) {
    uint32_t i = wint_ru32(w->m, &x->pc), slot = w->frames[x->nf - 1].base + i;
    if (op == 0x23) { WINT_PUSH(w, x, w->globals[i]); return WINT_OK; }
    WINT_NEED(x, 1);
    if (op == 0x24) { w->globals[i] = w->stack[--x->sp]; return WINT_OK; }
    if (slot >= x->sp && op == 0x20) return WINT_T_STACK;
    if (op == 0x20) { WINT_PUSH(w, x, w->stack[slot]); return WINT_OK; }
    w->stack[slot] = w->stack[x->sp - 1];
    if (op == 0x21) x->sp--;
    return WINT_OK;
}

static wint_status misc(wint* w, wint_ex* x, uint8_t op) {
    uint32_t pages = w->mem_len / WINT_PAGE;
    switch (op) {
    case 0x00: return WINT_T_UNREACHABLE;
    case 0x01: return WINT_OK;
    case 0x1A: WINT_NEED(x, 1); x->sp--; return WINT_OK;
    case 0x1C: x->pc += 2; /* fall through: the type vector of one */
    case 0x1B: {
        WINT_NEED(x, 3);
        uint32_t c = (uint32_t)w->stack[--x->sp];
        x->sp--;
        if (!c) w->stack[x->sp - 1] = w->stack[x->sp];
        return WINT_OK;
    }
    case 0x3F: x->pc++; WINT_PUSH(w, x, pages); return WINT_OK;
    case 0x40: x->pc++; WINT_NEED(x, 1); w->stack[x->sp - 1] = w->stack[x->sp - 1] ? 0xFFFFFFFFu : pages; return WINT_OK;
    case 0x41: WINT_PUSH(w, x, (uint32_t)wint_rs64(w->m, &x->pc)); return WINT_OK;
    case 0x42: WINT_PUSH(w, x, wint_rs64(w->m, &x->pc)); return WINT_OK;
    case 0x43: case 0x44: {
        uint32_t n = op == 0x43 ? 4 : 8;
        uint64_t v = rd(w->m + x->pc, n);
        x->pc += n;
        WINT_PUSH(w, x, v);
        return WINT_OK;
    }
    case 0xFC: return bulk(w, x);
    default: WINT_NEED(x, wint_num_arity(op)); return wint_num(op, w->stack, &x->sp);
    }
}

static wint_status step(wint* w, wint_ex* x, int* done) {
    uint8_t op = w->m[x->pc++];
    switch (op) {
    case 0x02: case 0x03: case 0x04: return wint_flow_block(w, x, op);
    case 0x05: case 0x0B: return wint_flow_end(w, x, op, done);
    case 0x0C: return wint_flow_br(w, x, wint_ru32(w->m, &x->pc), done);
    case 0x0D: {
        uint32_t l = wint_ru32(w->m, &x->pc);
        WINT_NEED(x, 1);
        return (uint32_t)w->stack[--x->sp] ? wint_flow_br(w, x, l, done) : WINT_OK;
    }
    case 0x0E: {
        uint32_t n = wint_ru32(w->m, &x->pc), pick, l = 0;
        WINT_NEED(x, 1);
        pick = (uint32_t)w->stack[--x->sp];
        for (uint32_t i = 0; i <= n; i++) {
            uint32_t li = wint_ru32(w->m, &x->pc);
            if (i == pick || i == n) { l = li; if (i == pick) break; }
        }
        return wint_flow_br(w, x, l, done);
    }
    case 0x0F: return wint_flow_br(w, x, x->nl - 1 - w->frames[x->nf - 1].labels, done);
    case 0x10: return wint_flow_call(w, x, wint_ru32(w->m, &x->pc));
    default: break;
    }
    if (op >= 0x20 && op <= 0x24) return var_op(w, x, op);
    if (op >= 0x28 && op <= 0x3E) return mem_op(w, x, op);
    return misc(w, x, op);
}

wint_status wint_call(wint* w, int func, const uint64_t* args, int nargs, uint64_t* result, uint32_t fuel) {
    if (func < 0 || func >= w->nfuncs || nargs != w->types[w->funcs[func].type].np) return WINT_T_TYPE;
    wint_ex x = {0, 0, 0, 0};
    for (int i = 0; i < nargs; i++) w->stack[x.sp++] = args[i];
    w->fuel = fuel;
    int done = w->funcs[func].imported;
    wint_status st = wint_flow_call(w, &x, (uint32_t)func);
    while (!st && !done) {
        if (!w->fuel--) { st = WINT_T_FUEL; break; }
        w->steps++;
        st = step(w, &x, &done);
    }
    *result = !st && x.sp ? w->stack[0] : 0;
    return st;
}
