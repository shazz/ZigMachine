/* Native test of fpga/glass/firmware/glass_input.c: each event must make the
 * cart calls docs/sealed-loader.js makes for the same key. Built and run by
 * tests/test_glass.py with the map's -D defines. */
#include <stdio.h>
#include <string.h>

#include "glass_input.h"

static char log_buf[512];
static int failures;

static void record(void* ctx, const char* name, int arg) {
    (void)ctx;
    char one[48];
    snprintf(one, sizeof one, "%s%s(%d)", log_buf[0] ? " " : "", name, arg);
    strncat(log_buf, one, sizeof log_buf - strlen(log_buf) - 1);
}

static void expect(uint32_t ev, int owns, const char* want) {
    log_buf[0] = 0;
    glass_dispatch(ev, owns, record, NULL);
    if (strcmp(log_buf, want) != 0) {
        printf("FAIL event 0x%x owns %d: got \"%s\" want \"%s\"\n", (unsigned)ev, owns, log_buf, want);
        failures++;
    }
}

static void record_pointer(void* ctx, int x, int y, uint32_t buttons) {
    (void)ctx;
    char one[48];
    snprintf(one, sizeof one, "%spointer(%d,%d,%u)", log_buf[0] ? " " : "", x, y, (unsigned)buttons);
    strncat(log_buf, one, sizeof log_buf - strlen(log_buf) - 1);
}

static uint32_t ptr(uint32_t x, uint32_t y, uint32_t btn, uint32_t seq) {
    return x << PTR_X_SHIFT | y << PTR_Y_SHIFT | btn << PTR_BTN_SHIFT | seq << PTR_SEQ_SHIFT;
}

/* One poll; `want_ack` is what the firmware must write to glass_pointer_ack (-1: none). */
static void expect_ptr(uint32_t word, uint32_t* seen, glass_pointer_fn fn, const char* want, int want_ack) {
    log_buf[0] = 0;
    int got = glass_pointer(word, seen, fn, NULL);
    if (strcmp(log_buf, want) != 0 || got != want_ack) {
        printf("FAIL pointer 0x%x: got \"%s\" ack %d want \"%s\" ack %d\n", (unsigned)word, log_buf, got, want, want_ack);
        failures++;
    }
}

static void test_pointer(void) {
    uint32_t seen = 0;
    expect_ptr(ptr(0, 0, 0, 0), &seen, record_pointer, "", -1);  /* never touched: no call */
    expect_ptr(ptr(639, 199, PTR_BTN_PRESS, 1), &seen, record_pointer, "pointer(639,199,1)", 1);
    expect_ptr(ptr(639, 199, PTR_BTN_PRESS, 1), &seen, record_pointer, "", -1);  /* same SEQ: once */
    expect_ptr(ptr(12, 34, PTR_BTN_DOUBLE | PTR_BTN_PRESS, 2), &seen, record_pointer, "pointer(12,34,3)", 2);
    expect_ptr(ptr(12, 34, 0, 0), &seen, record_pointer, "pointer(12,34,0)", 0);  /* SEQ wraps */
    seen = 0;
    expect_ptr(ptr(5, 6, PTR_BTN_PRESS, 7), &seen, NULL, "", 7);  /* no pointer(): acked, not called */
    if (seen != 7) {
        printf("FAIL pointer: a cart without pointer() must still advance SEQ (seen %u)\n", (unsigned)seen);
        failures++;
    }
}

int main(void) {
    const uint32_t D = KEY_DOWN, R = KEY_REPEAT;
    expect(D | KEY_ARROW_UP, 0, "input(0)");
    expect(D | KEY_ARROW_UP, 1, "input(0)");               /* arrows stay movement for an owning app */
    expect(KEY_ARROW_UP, 1, "inputRelease(0)");
    expect(D | 'w', 0, "input(0) key(119)");
    expect(D | 'w', 1, "key(119)");                        /* W is a letter for an app that owns keys */
    expect(D | 'W', 0, "key(87)");                         /* shifted: not a direction, as evt.key */
    expect(D | ' ', 0, "input(5) key(32)");
    expect(D | KEY_ENTER, 0, "input(5) key(13)");
    expect(KEY_ENTER, 0, "inputRelease(5) keyUp(13)");
    expect(D | '3', 0, "setShadeMode(2) key(51)");
    expect(D | '3', 1, "key(51)");
    expect(D | '+', 0, "");                                /* the channel buttons: the OSD's job */
    expect(D | '+', 1, "key(43)");
    expect(D | KEY_ESCAPE, 0, "key(57362)");
    expect(D | KEY_SHIFT_LEFT, 0, "key(57365)");
    expect(D | R | KEY_SHIFT_LEFT, 0, "");                 /* a modifier's repeat is not sent */
    expect(D | R | 'x', 1, "key(120)");                    /* other repeats are */
    expect(KEY_SHIFT_LEFT, 0, "keyUp(57365)");
    log_buf[0] = 0;
    glass_joy(0, JOY_LEFT | JOY_FIRE, record, NULL);
    glass_joy(JOY_LEFT | JOY_FIRE, JOY_FIRE, record, NULL);
    if (strcmp(log_buf, "input(2) input(5) inputRelease(2)") != 0) {
        printf("FAIL joy: \"%s\"\n", log_buf);
        failures++;
    }
    test_pointer();
    if (failures) return 1;
    printf("glass_input: ok\n");
    return 0;
}
