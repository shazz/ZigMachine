/* wint's control flow (wint_exec.h): structured blocks through the jump tables wint_scan.c
 * filled, branches that carry their block's values, and calls with their locals on the value
 * stack. Every stack, label and frame index is checked against its array. */
#include <string.h>

#include "wint_exec.h"
#include "wint_leb.h"

static void block_arity(const wint* w, const uint8_t* m, uint32_t* pc, uint32_t* np, uint32_t* nr) {
    uint8_t b = m[*pc];
    if (b == 0x40) { (*pc)++; *np = *nr = 0; return; }
    if ((b & 0xC0) == 0x40) { (*pc)++; *np = 0; *nr = 1; return; } /* a value type: 0x7F, 0x7E, 0x6F ... */
    uint64_t t = wint_rs64(m, pc); /* a type index, checked by the scan */
    *np = w->types[t].np, *nr = w->types[t].nr;
}

static wint_status push_label(wint* w, wint_ex* x, uint32_t cont, uint32_t height, uint32_t arity, int loop) {
    if (x->nl >= WINT_LABELS) return WINT_T_STACK;
    w->labels[x->nl++] = (wint_label){(uint16_t)cont, (uint16_t)height, (uint8_t)arity, (uint8_t)loop};
    return WINT_OK;
}

wint_status wint_flow_block(wint* w, wint_ex* x, uint8_t op) {
    uint32_t at = x->pc - 1, np, nr;
    if (op == 0x04) {
        WINT_NEED(x, 1);
        uint32_t c = (uint32_t)w->stack[--x->sp];
        block_arity(w, w->m, &x->pc, &np, &nr);
        WINT_NEED(x, np);
        if (!c && !w->alt[at]) { x->pc = w->jump[at] + 1u; return WINT_OK; } /* no else: skip it all */
        if (!c) x->pc = w->alt[at] + 1u;
        return push_label(w, x, w->jump[at] + 1u, x->sp - np, nr, 0);
    }
    block_arity(w, w->m, &x->pc, &np, &nr);
    WINT_NEED(x, np);
    if (op == 0x03) return push_label(w, x, x->pc, x->sp - np, np, 1);
    return push_label(w, x, w->jump[at] + 1u, x->sp - np, nr, 0);
}

/* Leave the current function: its results to where its locals began. */
static wint_status ret(wint* w, wint_ex* x, int* done) {
    wint_frame* f = &w->frames[x->nf - 1];
    uint32_t nr = w->types[w->funcs[f->func].type].nr;
    WINT_NEED(x, f->base + nr);
    memmove(&w->stack[f->base], &w->stack[x->sp - nr], nr * sizeof w->stack[0]);
    x->sp = f->base + nr;
    x->nl = f->labels;
    x->pc = f->ret;
    *done = --x->nf == 0;
    return WINT_OK;
}

wint_status wint_flow_br(wint* w, wint_ex* x, uint32_t l, int* done) {
    uint32_t floor = w->frames[x->nf - 1].labels;
    if (l >= x->nl - floor) return WINT_T_STACK;
    wint_label* L = &w->labels[x->nl - 1 - l];
    if (L->cont == WINT_RET) return ret(w, x, done);
    WINT_NEED(x, L->height + L->arity);
    memmove(&w->stack[L->height], &w->stack[x->sp - L->arity], L->arity * sizeof w->stack[0]);
    x->sp = L->height + L->arity;
    x->pc = L->cont;
    x->nl -= l + (L->loop ? 0 : 1);
    return WINT_OK;
}

wint_status wint_flow_end(wint* w, wint_ex* x, uint8_t op, int* done) {
    if (x->nl <= w->frames[x->nf - 1].labels) return WINT_T_STACK;
    if (op == 0x05) { /* the true branch is over: to the if's end, values kept */
        x->pc = w->jump[x->pc - 1] + 1u;
        x->nl--;
        return WINT_OK;
    }
    if (w->labels[x->nl - 1].cont == WINT_RET) return ret(w, x, done);
    x->nl--;
    return WINT_OK;
}

static wint_status host_call(wint* w, wint_ex* x, const wint_func* f) {
    const wint_type* t = &w->types[f->type];
    WINT_NEED(x, t->np);
    x->sp -= t->np;
    uint64_t r = f->host ? f->host(w->ctx, &w->stack[x->sp]) : 0; /* no such host import: the browser's stub */
    if (t->nr) WINT_PUSH(w, x, t->nr == 1 ? r : 0);
    return WINT_OK;
}

wint_status wint_flow_call(wint* w, wint_ex* x, uint32_t func) {
    const wint_func* f = &w->funcs[func];
    if (f->imported) return host_call(w, x, f);
    const wint_type* t = &w->types[f->type];
    WINT_NEED(x, t->np);
    uint32_t base = x->sp - t->np;
    if (x->nf >= WINT_FRAMES || f->nlocals > WINT_STACK - x->sp) return WINT_T_STACK;
    memset(&w->stack[x->sp], 0, f->nlocals * sizeof w->stack[0]);
    x->sp += f->nlocals;
    w->frames[x->nf++] = (wint_frame){(uint16_t)func, (uint16_t)x->pc, (uint16_t)base, (uint16_t)x->nl};
    x->pc = f->body;
    return push_label(w, x, WINT_RET, x->sp, t->nr, 0);
}
