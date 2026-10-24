/* wint: a small, sandboxed WebAssembly interpreter for a disk's 1 KB executable boot sector
 * (ZigCart format v2, docs/FLOPPY_DISK.md), so the board runs the sector's OWN bytes as the
 * browser does (host/bootsec.h). Not a general engine: the integer MVP, the f32/f64 bit moves
 * (const, load, store, reinterpret), sign extension, memory.fill/copy, multi-value blocks.
 * Float arithmetic, call_indirect, tables and passive data are refused when the module loads.
 *
 * Nothing a module does can reach outside its sandbox: every opcode and immediate is checked
 * once at load (wint_scan.c), every memory access against the imported memory's length, the
 * value/label/call stacks against their arrays, and each call runs on a FUEL budget (one unit
 * an instruction) so a loop that never ends traps instead of hanging the firmware.
 * The whole state is one struct the caller owns (the firmware keeps it on its stack: no
 * statics, so the system image's data layout does not move). Plain C, no libc beyond string.h. */
#ifndef ZM_WINT_H
#define ZM_WINT_H

#include <stdint.h>

/* The limits fit a 1 KB sector; tests/tb/bootsec_test.c raises them for its opcode module. */
#ifndef WINT_MAX_BYTES
#define WINT_MAX_BYTES 1024u /* a v2 boot sector */
#define WINT_MAX_TYPES 16
#define WINT_MAX_FUNCS 32
#define WINT_MAX_EXPORTS 16
#endif
#define WINT_MAX_GLOBALS 8
#define WINT_MAX_DATA 8
#define WINT_MAX_ARGS 8
#define WINT_STACK 512 /* value slots: locals and operands of every frame */
#define WINT_LABELS 128
#define WINT_FRAMES 48
#define WINT_PAGE 65536u
#define WINT_NO_FUNC 0xFFFFu
#define WINT_RET 0xFFFFu

typedef enum {
    WINT_OK = 0,
    WINT_E_FORMAT,      /* not a wasm module, or one the parser cannot read */
    WINT_E_UNSUPPORTED, /* valid wasm, outside wint's subset */
    WINT_E_LINK,        /* an import or a data segment the memory cannot take */
    WINT_T_UNREACHABLE, /* the traps, as the browser's RuntimeError */
    WINT_T_OOB,
    WINT_T_DIV,
    WINT_T_STACK,
    WINT_T_FUEL,
    WINT_T_TYPE, /* a call whose arguments do not match the function */
} wint_status;

/* A host import: its arguments (the function type's params, low bits for i32), its result
 * (ignored for a function with none). */
typedef uint64_t (*wint_host_fn)(void* ctx, const uint64_t* args);
typedef struct {
    const char* name; /* the "env" import's name */
    wint_host_fn fn;
} wint_import;

typedef struct {
    uint8_t np, nr;
} wint_type;

typedef struct {
    uint16_t type;
    uint16_t body, end; /* the first instruction, and one past the body's final `end` */
    uint16_t nlocals;   /* declared locals (params not counted) */
    wint_host_fn host;  /* an import: the host's, or NULL for a stub answering 0 */
    uint8_t imported;
} wint_func;

typedef struct {
    uint16_t name, name_len, func; /* the name's bytes in the module */
} wint_export;

typedef struct {
    uint32_t at, from, len; /* memory offset; module offset and length of the bytes */
} wint_data;

typedef struct {
    uint16_t cont, height; /* where a br goes (WINT_RET: out of the function); the height under the block */
    uint8_t arity, loop;   /* values a br carries; a loop keeps its label when branched to */
} wint_label;

typedef struct {
    uint16_t func, ret, base, labels; /* locals start at stack[base]; labels below the frame */
} wint_frame;

typedef struct wint {
    const uint8_t* m;
    uint32_t len;
    uint8_t* mem; /* the imported env.memory */
    uint32_t mem_len;
    void* ctx;
    const wint_import* host;
    int nhost;
    uint16_t ntypes, nfuncs, nglobals, nexports, ndata, start;
    wint_type types[WINT_MAX_TYPES];
    wint_func funcs[WINT_MAX_FUNCS];
    uint64_t globals[WINT_MAX_GLOBALS];
    uint8_t gmut[WINT_MAX_GLOBALS];
    wint_export exports[WINT_MAX_EXPORTS];
    wint_data data[WINT_MAX_DATA];
    uint16_t jump[WINT_MAX_BYTES]; /* at block/loop/if/else: its matching `end` */
    uint16_t alt[WINT_MAX_BYTES];  /* at an if: its `else`, 0 when it has none */
    uint64_t stack[WINT_STACK];
    wint_label labels[WINT_LABELS];
    wint_frame frames[WINT_FRAMES];
    uint32_t fuel;
    uint32_t steps; /* instructions executed over every call (the cost report) */
    const char* why; /* what the last failure was, for the console */
} wint;

/* Parse and check `m` (len <= WINT_MAX_BYTES), link its imports (memory: `mem`, functions:
 * `host` by name, any other env function a stub answering 0, as the browser's loader stubs
 * what it lacks), write its data segments and run its start function. */
wint_status wint_load(wint* w, const uint8_t* m, uint32_t len, uint8_t* mem, uint32_t mem_len,
                      const wint_import* host, int nhost, void* ctx);

/* The function an export names, or -1. */
int wint_export_func(const wint* w, const char* name);

/* Call function `func` with `nargs` arguments; its first result (if any) in *result. At most
 * `fuel` instructions. A trap leaves the instance usable for the next call. */
wint_status wint_call(wint* w, int func, const uint64_t* args, int nargs, uint64_t* result, uint32_t fuel);

/* Internal: the body checker (wint_scan.c: `nloc` = params + locals), the numeric ops (wint_num.c). */
wint_status wint_scan(wint* w, uint32_t body, uint32_t end, uint32_t nloc);
/* One numeric opcode on the stack (sp: slots used). WINT_OK, a trap, or WINT_E_UNSUPPORTED
 * when `op` is not a numeric opcode. The caller checked the stack holds its operands. */
wint_status wint_num(uint8_t op, uint64_t* st, uint32_t* sp);
/* Operands an opcode pops (wint_num's): 1 or 2, 0 for a non-numeric opcode. */
int wint_num_arity(uint8_t op);

#endif
