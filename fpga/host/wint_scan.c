/* wint's body checker (wint.h): walks one function body once at load, so the interpreter
 * never meets an opcode it does not run, an immediate that runs off the body, a branch to a
 * label that does not exist, or a block without its `end`. It also fills the jump tables:
 * every block/loop/if (and else) to its matching `end`, every if to its `else`. */
#include "wint.h"
#include "wint_leb.h"

#define FAIL(st, msg) do { w->why = (msg); return (st); } while (0)
#define U32(v) do { if (wint_u32(w->m, end, &pc, (v))) FAIL(WINT_E_FORMAT, "truncated immediate"); } while (0)

typedef struct {
    uint16_t at[WINT_LABELS]; /* the block/loop/if's pc */
    uint16_t els[WINT_LABELS];
    uint32_t n;
} open_t;

static wint_status blocktype(wint* w, uint32_t end, uint32_t* pc) {
    uint64_t t;
    if (*pc >= end) FAIL(WINT_E_FORMAT, "block type");
    uint8_t b = w->m[*pc];
    if (b == 0x40 || b == 0x7F || b == 0x7E || b == 0x7D || b == 0x7C || b == 0x7B || b == 0x70 || b == 0x6F) {
        (*pc)++;
        return WINT_OK;
    }
    if (wint_leb(w->m, end, pc, 33, 1, &t) || t >= w->ntypes) FAIL(WINT_E_FORMAT, "block type index");
    return WINT_OK;
}

static wint_status label(wint* w, uint32_t end, uint32_t* pc, uint32_t depth) {
    uint32_t l;
    if (wint_u32(w->m, end, pc, &l) || l > depth) FAIL(WINT_E_FORMAT, "branch to no label");
    return WINT_OK;
}

static wint_status zeros(wint* w, uint32_t end, uint32_t* pc, uint32_t n) {
    for (uint32_t i = 0; i < n; i++, (*pc)++)
        if (*pc >= end || w->m[*pc] != 0) FAIL(WINT_E_UNSUPPORTED, "a memory other than 0");
    return WINT_OK;
}

/* Immediates of the opcodes that take no control action. */
static wint_status plain(wint* w, uint8_t op, uint32_t end, uint32_t* pc, uint32_t nloc) {
    uint32_t a, b;
    uint64_t v;
    if (op == 0x00 || op == 0x01 || op == 0x0F || op == 0x1A || op == 0x1B || wint_num_arity(op)) return WINT_OK;
    if (op == 0x10) {
        if (wint_u32(w->m, end, pc, &a) || a >= w->nfuncs) FAIL(WINT_E_FORMAT, "call to no function");
    } else if (op == 0x1C) {
        if (end - *pc < 2 || w->m[*pc] != 1) FAIL(WINT_E_FORMAT, "select type"); /* exactly 2 bytes: wint_exec.c */
        *pc += 2;
    } else if (op >= 0x20 && op <= 0x22) {
        if (wint_u32(w->m, end, pc, &a) || a >= nloc) FAIL(WINT_E_FORMAT, "no such local");
    } else if (op == 0x23 || op == 0x24) {
        if (wint_u32(w->m, end, pc, &a) || a >= w->nglobals) FAIL(WINT_E_FORMAT, "no such global");
        if (op == 0x24 && !w->gmut[a]) FAIL(WINT_E_FORMAT, "set of an immutable global");
    } else if (op >= 0x28 && op <= 0x3E) {
        if (wint_u32(w->m, end, pc, &a) || a >= 32 || wint_u32(w->m, end, pc, &b)) FAIL(WINT_E_FORMAT, "memarg");
    } else if (op == 0x3F || op == 0x40) {
        return zeros(w, end, pc, 1);
    } else if (op == 0x41 || op == 0x42) {
        if (wint_leb(w->m, end, pc, op == 0x41 ? 32 : 64, 1, &v)) FAIL(WINT_E_FORMAT, "constant");
    } else if (op == 0x43 || op == 0x44) {
        a = op == 0x43 ? 4 : 8;
        if (a > end - *pc) FAIL(WINT_E_FORMAT, "constant");
        *pc += a;
    } else if (op == 0xFC) {
        if (wint_u32(w->m, end, pc, &a) || (a != 10 && a != 11)) FAIL(WINT_E_UNSUPPORTED, "an 0xFC op other than memory.copy/fill");
        return zeros(w, end, pc, a == 10 ? 2 : 1);
    } else {
        FAIL(WINT_E_UNSUPPORTED, "an opcode wint does not run (float arithmetic, call_indirect, tables...)");
    }
    return WINT_OK;
}

static wint_status close_block(wint* w, open_t* o, uint32_t at) {
    uint32_t k = --o->n;
    w->jump[o->at[k]] = (uint16_t)at;
    if (o->els[k]) w->jump[o->els[k]] = (uint16_t)at;
    return WINT_OK;
}

wint_status wint_scan(wint* w, uint32_t body, uint32_t end, uint32_t nloc) {
    open_t o;
    o.n = 0;
    uint32_t pc = body;
    while (pc < end) {
        uint32_t at = pc;
        uint8_t op = w->m[pc++];
        wint_status st = WINT_OK;
        if (op == 0x02 || op == 0x03 || op == 0x04) {
            if (o.n >= WINT_LABELS) FAIL(WINT_E_UNSUPPORTED, "blocks nested too deep");
            o.at[o.n] = (uint16_t)at, o.els[o.n++] = 0;
            w->alt[at] = 0;
            st = blocktype(w, end, &pc);
        } else if (op == 0x05) {
            if (!o.n || w->m[o.at[o.n - 1]] != 0x04 || o.els[o.n - 1]) FAIL(WINT_E_FORMAT, "else without its if");
            o.els[o.n - 1] = (uint16_t)at;
            w->alt[o.at[o.n - 1]] = (uint16_t)at;
        } else if (op == 0x0B) {
            if (!o.n) return pc == end ? WINT_OK : (w->why = "code after the function's end", WINT_E_FORMAT);
            st = close_block(w, &o, at);
        } else if (op == 0x0C || op == 0x0D) {
            st = label(w, end, &pc, o.n);
        } else if (op == 0x0E) {
            uint32_t n;
            U32(&n);
            if (n > end - pc) FAIL(WINT_E_FORMAT, "br_table");
            for (uint32_t i = 0; i <= n && !st; i++) st = label(w, end, &pc, o.n);
        } else {
            st = plain(w, op, end, &pc, nloc);
        }
        if (st) return st;
    }
    FAIL(WINT_E_FORMAT, "a body without its end");
}
