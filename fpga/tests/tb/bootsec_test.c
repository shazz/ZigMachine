/* host/bootsec.c and host/wint*.c on the PC, for tests/test_board_bootsec.py, which runs the
 * same modules in node's WebAssembly (the browser's engine) and compares every line.
 *
 *   bootsec_test sector FILE FRAMES   FILE: a .zmd (its 1 KB sector) or a bare .wasm. Memory of
 *       112 pages seeded i*7, hwVideoBase = VBASE with the plane-0 pointer at VBASE+68 = FB.
 *       Prints "boot <status> <fnv>", then per frame "f <n> <rc> <plane0> <fnv>".
 *   bootsec_test calls FILE <LINES   "EXPORT ARG..." per line (ARGs i64 decimal): "<status> <result>".
 *   bootsec_test exec FILE   bootsec_executable() of a disk: 0 or 1. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bootsec.h"

#define PAGES 112u
#define MEM (PAGES * WINT_PAGE)
#define VBASE 0x200000u
#define FB 0x1000u

static uint8_t g_mem[MEM];
static uint8_t g_file[1 << 20];
static bootsec_t g_b;

static uint32_t fnv(void) {
    uint32_t h = 2166136261u;
    for (uint32_t i = 0; i < MEM; i++) h = (h ^ g_mem[i]) * 16777619u;
    return h;
}

static uint32_t load(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) { perror(path); exit(2); }
    uint32_t n = (uint32_t)fread(g_file, 1, sizeof g_file, f);
    fclose(f);
    return n;
}

static void seed(void) {
    for (uint32_t i = 0; i < MEM; i++) g_mem[i] = (uint8_t)(i * 7);
    memcpy(g_mem + VBASE + 68, &(uint32_t){FB}, 4);
}

static int sector(const char* path, long frames) {
    uint32_t n = load(path);
    if (n < BOOTSEC_BYTES) memset(g_file + n, 0, BOOTSEC_BYTES - n); /* a bare .wasm: empty sections pad it */
    seed();
    wint_status st = bootsec_start(&g_b, g_file, g_mem, MEM, VBASE, NULL);
    printf("boot %s %08x\n", bootsec_status(st), fnv());
    for (long f = 1; f <= frames && !st; f++) {
        int rc = bootsec_frame(&g_b, 16.6f);
        int on = bootsec_plane_on(&g_b, 0);
        printf("f %ld %d %d %08x\n", f, rc, on, fnv());
        if (rc) break;
    }
    fprintf(stderr, "steps %lu\n", (unsigned long)g_b.w.steps);
    return 0;
}

static uint64_t imp_id(void* ctx, const uint64_t* a) { (void)ctx; return a[0]; }
static const wint_import TEST_IMPORTS[] = {{"id", imp_id}};

/* A line "EXPORT ARG..." per call on stdin, one instance for all of them (a trap must leave
 * it usable, as a browser instance is): "ok RESULT" or "<trap> 0" per line. */
static int calls(const char* path) {
    uint32_t n = load(path);
    char line[512];
    seed();
    wint_status st = wint_load(&g_b.w, g_file, n, g_mem, MEM, TEST_IMPORTS, 1, NULL);
    if (st) {
        printf("load %s\n", bootsec_status(st));
        fprintf(stderr, "why: %s\n", g_b.w.why ? g_b.w.why : "-");
        return 0;
    }
    while (fgets(line, sizeof line, stdin)) {
        uint64_t args[WINT_MAX_ARGS], r = 0;
        int argc = 0;
        char* tok = strtok(line, " \n");
        if (!tok) continue;
        int fn = wint_export_func(&g_b.w, tok);
        while ((tok = strtok(NULL, " \n")) && argc < WINT_MAX_ARGS) args[argc++] = (uint64_t)strtoll(tok, NULL, 10);
        st = fn < 0 ? WINT_E_LINK : wint_call(&g_b.w, fn, args, argc, &r, 1u << 22);
        printf("%s %lld\n", bootsec_status(st), st ? 0LL : (long long)r);
    }
    return 0;
}

int main(int argc, char** argv) {
    if (argc >= 4 && strcmp(argv[1], "sector") == 0) return sector(argv[2], strtol(argv[3], NULL, 10));
    if (argc >= 3 && strcmp(argv[1], "calls") == 0) return calls(argv[2]);
    if (argc >= 3 && strcmp(argv[1], "exec") == 0) return printf("%d\n", bootsec_executable(g_file, load(argv[2]))), 0;
    fprintf(stderr, "usage: bootsec_test sector FILE FRAMES | calls FILE <LINES | exec FILE\n");
    return 2;
}
