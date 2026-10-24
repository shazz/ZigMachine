/* wint's interpreter state between wint_exec.c (the loop, memory, locals) and wint_flow.c
 * (blocks, branches, calls, returns). Private to wint. */
#ifndef ZM_WINT_EXEC_H
#define ZM_WINT_EXEC_H

#include "wint.h"

typedef struct {
    uint32_t sp, nl, nf; /* used slots of w->stack, w->labels, w->frames */
    uint32_t pc;
} wint_ex;

#define WINT_PUSH(w, x, v) do { if ((x)->sp >= WINT_STACK) return WINT_T_STACK; (w)->stack[(x)->sp++] = (v); } while (0)
#define WINT_NEED(x, n) do { if ((x)->sp < (uint32_t)(n)) return WINT_T_STACK; } while (0)

/* Enter `func` (its arguments on the stack); a host import runs at once. `done` is set when
 * the outermost frame returned. */
wint_status wint_flow_call(wint* w, wint_ex* x, uint32_t func);
/* block / loop / if at x->pc - 1 (the opcode read). */
wint_status wint_flow_block(wint* w, wint_ex* x, uint8_t op);
/* br `l`; *done when it left the outermost function. */
wint_status wint_flow_br(wint* w, wint_ex* x, uint32_t l, int* done);
/* `end` (at x->pc - 1) or `else` reached in its true branch. */
wint_status wint_flow_end(wint* w, wint_ex* x, uint8_t op, int* done);

#endif
