// The BARD queue's ring (decisions.md 2026-11-07 "The BARD queue"; libs/zig/bard.zig is the reference for this C
// copy, as SID-WIZARD's kestrel_sw_bard.c is): commands {t, addr, value, seq} in the cart's memory, seq written
// last; a full ring drops the write (counted in the header); the cart never waits. The sound side (BARD on the
// board, the AudioWorklet on the page, host/audio_bardq.c natively) plays each at its sample, a lead behind the
// first batch. Events coming back are let go. ChipNomad's AY chips post on it (kestrel_chip.cpp).
#include <stdint.h>
#include <string.h>
#include "kestrel_bard.h"

extern "C" {
__attribute__((import_module("env"), import_name("hostBardAttach"))) uint32_t hostBardAttach(uint32_t block, uint32_t lead);
}

#define BQ_MAGIC 0x51424d5au // "ZMBQ"
#define BQ_CAP 256u          // commands (a power of two)
#define BQ_EV_CAP 16u
enum { W_MAGIC, W_CAP, W_EV_CAP, W_LEAD, W_HEAD, W_TAIL, W_DROPPED, W_POS, W_ANCHORED, W_EV_HEAD, W_EV_TAIL, W_EV_LOST };
struct bq_cmd { uint32_t t, addr, value, seq; };
static struct {
    uint32_t head[16];
    bq_cmd cmds[BQ_CAP];
    bq_cmd events[BQ_EV_CAP];
} bq __attribute__((aligned(16)));
static int bq_open_;

static volatile uint32_t* word(int i) { return &bq.head[i]; }

// bard.open(): the header, every seq not its index, then the host's answer (0: no queue on this host).
int kestrel_bq_open(uint32_t lead)
{
    memset(bq.head, 0, sizeof bq.head);
    for (unsigned i = 0; i < BQ_CAP; i++) ((volatile bq_cmd*)&bq.cmds[i])->seq = 0xFFFFFFFFu;
    *word(W_CAP) = BQ_CAP;
    *word(W_EV_CAP) = BQ_EV_CAP;
    *word(W_LEAD) = lead;
    *word(W_MAGIC) = BQ_MAGIC;
    bq_open_ = hostBardAttach((uint32_t)(uintptr_t)&bq, lead) != 0;
    return bq_open_;
}

void kestrel_bq_close(void)
{
    if (bq_open_) hostBardAttach(0, 0);
    bq_open_ = 0;
}

int kestrel_bq_is_open(void) { return bq_open_; }

int kestrel_bq_push(uint32_t t, uint32_t addr, uint32_t value)
{
    if (!bq_open_) return 0;
    uint32_t head = *word(W_HEAD);
    if (head - *word(W_TAIL) >= BQ_CAP) { *word(W_DROPPED) += 1; return 0; }
    volatile bq_cmd* c = &bq.cmds[head % BQ_CAP];
    c->t = t; c->addr = addr; c->value = value;
    c->seq = head; // last: the entry is whole when its seq is its index
    *word(W_HEAD) = head + 1;
    return 1;
}

void kestrel_bq_frame(void)
{
    if (bq_open_) *word(W_EV_TAIL) = *word(W_EV_HEAD);
}

uint32_t kestrel_bq_dropped(void) { return *word(W_DROPPED); }
