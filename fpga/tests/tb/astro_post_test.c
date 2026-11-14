/* ZIGGY's side of ASTROLABE's mailbox (cycles/bastro_post.h), natively, against a scripted
 * glass that acts whenever the firmware reads its clock (tests/test_astro_box.py). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cycles/bastro_post.h"

static int failures;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); failures++; } } while (0)

static uint32_t box[1024];
static uint8_t mem[4096] __attribute__((aligned(8)));
static uint32_t now, last_served, serves, late_from;
static enum { SERVE, NEVER, TAKE_ONLY, LATE } glass;

static double get64(const uint32_t* w) { uint64_t b = (uint64_t)w[1] << 32 | w[0]; double d; memcpy(&d, &b, 8); return d; }
static void put64(uint32_t* w, double d) { uint64_t b; memcpy(&b, &d, 8); w[0] = (uint32_t)b, w[1] = (uint32_t)(b >> 32); }

/* glass: a MUL of S0 and S1 for each descriptor, status SERVED_ARM (0x100) */
static void glass_poll(void) {
    uint32_t seq = box[ASTRO_SEQ];
    if (seq == 0 || seq == last_served || glass == NEVER || (glass == LATE && now < late_from)) return;
    box[ASTRO_TAKEN] = seq;
    last_served = seq;
    if (glass == TAKE_ONLY) return;
    serves++;
    for (uint32_t i = 0; i < box[ASTRO_COUNT]; i++) {
        uint32_t* d = &box[ASTRO_DESC0 + i * ASTRO_DESC_WORDS];
        put64(&d[ASTRO_W_R], get64(&d[ASTRO_W_S0]) * get64(&d[ASTRO_W_S0 + 2]));
        d[ASTRO_W_STATUS] = 0x100;
    }
    box[ASTRO_ARM_NS] = 777, box[ASTRO_RET] = 0, box[ASTRO_DONE] = seq;
}
static uint32_t micros(void) { glass_poll(); return now++; }

static bastro_ctx ctx(void) {
    return (bastro_ctx){.box = box, .mem = mem, .size = sizeof mem, .mem_off = 0x123400, .micros = micros};
}

static uint32_t* desc(uint32_t at) { return (uint32_t*)(mem + at); }

static void scalar(uint32_t at, double a, double b) {
    memset(desc(at), 0, 80);
    desc(at)[ASTRO_W_OP] = 0x03; /* MUL */
    desc(at)[ASTRO_W_N] = 0xBADBAD; /* not a scalar op's word: never copied */
    put64(&desc(at)[ASTRO_W_S0], a), put64(&desc(at)[ASTRO_W_S0 + 2], b), put64(&desc(at)[ASTRO_W_S0 + 4], -1.25);
}

static void live(void) {
    memset(box, 0, sizeof box);
    box[ASTRO_MAGIC] = ASTRO_ID, box[ASTRO_VERSION] = ASTRO_PROTO;
    last_served = 0, serves = 0;
}

int main(void) {
    bastro_ctx c = ctx();
    live();
    glass = SERVE;
    scalar(0x100, 6, 7), scalar(0x150, 1.5, 2);
    CHECK(bastro_post(&c, 0x100, 2) == 0, "served");
    CHECK(get64(&desc(0x100)[ASTRO_W_R]) == 42 && get64(&desc(0x150)[ASTRO_W_R]) == 3, "results back in the cart's memory");
    CHECK(desc(0x100)[ASTRO_W_STATUS] == 0x100, "status back");
    CHECK(box[ASTRO_DESC0 + ASTRO_W_N] == 0, "a scalar op's W_N was copied in");
    CHECK(get64(&box[ASTRO_DESC0 + ASTRO_W_S0 + 4]) == -1.25, "S2 (FMA's addend) copied in");
    CHECK(box[ASTRO_MEM_OFF] == 0x123400 && box[ASTRO_MEM_SIZE] == sizeof mem && c.arm_ns == 777, "the memory's place, ARM_NS");
    CHECK(!c.arrays, "no array op");

    desc(0x200)[ASTRO_W_OP] = 0x20; /* VADD: W_N .. W_C and S0 copied, S1 not */
    for (uint32_t w = 1; w < 20; w++) desc(0x200)[w] = 0x1000 + w;
    CHECK(bastro_post(&c, 0x200, 1) == 0 && c.arrays, "an array op, served");
    for (uint32_t w = 1; w <= 6; w++) CHECK(box[ASTRO_DESC0 + w] == 0x1000 + w, "array word %u", w);
    CHECK(box[ASTRO_DESC0 + 10] == 0x100A && box[ASTRO_DESC0 + 11] == 0x100B, "S0");
    CHECK(box[ASTRO_DESC0 + 12] == 0, "S1 copied for an array op");

    CHECK(bastro_post(&c, 0x104, 1) == ASTRO_ST_BAD_DESC, "a misaligned list");
    CHECK(bastro_post(&c, 0x100, ASTRO_MAX_COUNT + 1) == ASTRO_ST_BAD_DESC, "too many");
    CHECK(bastro_post(&c, sizeof mem - 40, 1) == ASTRO_ST_BAD_DESC, "past the memory");
    CHECK(bastro_post(&c, 0x100, 0) == BASTRO_UNSERVED, "an empty list goes to the machine");

    box[ASTRO_MAGIC] = 0; /* no worker */
    uint32_t seq_before = box[ASTRO_SEQ];
    CHECK(bastro_post(&c, 0x100, 1) == BASTRO_UNSERVED && box[ASTRO_SEQ] == seq_before, "no MAGIC: nothing posted");
    live();
    glass = NEVER;
    uint32_t t0 = now;
    CHECK(bastro_post(&c, 0x100, 1) == BASTRO_UNSERVED, "not taken: the machine's code");
    CHECK(now - t0 >= BASTRO_TAKE_US && box[ASTRO_SEQ] == 0 && c.untaken == 1, "waited TAKE_US, then withdrew");
    glass = SERVE;
    t0 = now;
    CHECK(bastro_post(&c, 0x100, 1) == BASTRO_UNSERVED && now - t0 < 5 && serves == 0, "dead until the BEAT moves");
    box[ASTRO_BEAT]++;
    CHECK(bastro_post(&c, 0x100, 1) == 0 && serves == 1, "alive again once it moved");
    glass = TAKE_ONLY;
    CHECK(bastro_post(&c, 0x100, 1) == ASTRO_ST_TIMEOUT && c.timeouts == 1, "taken, never done: TIMEOUT, no rerun");
    live();
    c.dead = 0;
    glass = LATE;
    late_from = now + BASTRO_TAKE_US + 10;
    CHECK(bastro_post(&c, 0x100, 1) == BASTRO_UNSERVED && serves == 0, "a worker that wakes after the withdrawal serves nothing");
    for (int i = 0; i < 4; i++) micros();
    CHECK(serves == 0, "the withdrawn request was served late");
    if (failures) return 1;
    printf("astro_post: OK\n");
    return 0;
}
