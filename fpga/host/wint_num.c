/* wint's numeric opcodes (wint.h): i32 and i64 tests, comparisons and arithmetic, the
 * conversions between them, sign extension and the float reinterprets (bits only). An i32
 * lives zero-extended in its 64-bit slot. Division traps as wasm's does: by zero, and
 * INT_MIN / -1 (whose remainder is 0, no trap). Shift and rotate counts are taken mod width. */
#include "wint.h"

int wint_num_arity(uint8_t op) {
    if (op == 0x45 || op == 0x50 || (op >= 0x67 && op <= 0x69) || (op >= 0x79 && op <= 0x7B)) return 1;
    if (op == 0xA7 || op == 0xAC || op == 0xAD || (op >= 0xBC && op <= 0xC4)) return 1;
    if ((op >= 0x46 && op <= 0x4F) || (op >= 0x51 && op <= 0x5A)) return 2;
    if ((op >= 0x6A && op <= 0x78) || (op >= 0x7C && op <= 0x8A)) return 2;
    return 0;
}

static uint32_t clz32(uint32_t x) { return x ? (uint32_t)__builtin_clz(x) : 32; }
static uint32_t ctz32(uint32_t x) { return x ? (uint32_t)__builtin_ctz(x) : 32; }
static uint64_t clz64(uint64_t x) { return x ? (uint64_t)__builtin_clzll(x) : 64; }
static uint64_t ctz64(uint64_t x) { return x ? (uint64_t)__builtin_ctzll(x) : 64; }

static wint_status unary(uint8_t op, uint64_t* v) {
    uint32_t a = (uint32_t)*v;
    switch (op) {
    case 0x45: *v = a == 0; break;
    case 0x50: *v = *v == 0; break;
    case 0x67: *v = clz32(a); break;
    case 0x68: *v = ctz32(a); break;
    case 0x69: *v = (uint32_t)__builtin_popcount(a); break;
    case 0x79: *v = clz64(*v); break;
    case 0x7A: *v = ctz64(*v); break;
    case 0x7B: *v = (uint64_t)__builtin_popcountll(*v); break;
    case 0xA7: *v = a; break;                               /* i32.wrap_i64 */
    case 0xAC: *v = (uint64_t)(int64_t)(int32_t)a; break;  /* i64.extend_i32_s */
    case 0xAD: *v = a; break;                               /* i64.extend_i32_u */
    case 0xC0: *v = (uint32_t)(int32_t)(int8_t)a; break;
    case 0xC1: *v = (uint32_t)(int32_t)(int16_t)a; break;
    case 0xC2: *v = (uint64_t)(int64_t)(int8_t)*v; break;
    case 0xC3: *v = (uint64_t)(int64_t)(int16_t)*v; break;
    case 0xC4: *v = (uint64_t)(int64_t)(int32_t)*v; break;
    default: break; /* 0xBC..0xBF: reinterpret, the bits stay */
    }
    return WINT_OK;
}

static int cmp(uint8_t op, uint64_t a, uint64_t b, int wide) {
    int64_t sa = wide ? (int64_t)a : (int32_t)a, sb = wide ? (int64_t)b : (int32_t)b;
    switch ((op - (wide ? 0x51 : 0x46)) % 10) {
    case 0: return a == b;
    case 1: return a != b;
    case 2: return sa < sb;
    case 3: return a < b;
    case 4: return sa > sb;
    case 5: return a > b;
    case 6: return sa <= sb;
    case 7: return a <= b;
    case 8: return sa >= sb;
    default: return a >= b;
    }
}

static wint_status div32(uint8_t op, uint32_t a, uint32_t b, uint64_t* r) {
    if (b == 0) return WINT_T_DIV;
    int32_t sa = (int32_t)a, sb = (int32_t)b;
    int ovf = sa == INT32_MIN && sb == -1;
    if (op == 0x6D && ovf) return WINT_T_DIV;
    if (op == 0x6D) *r = (uint32_t)(sa / sb);
    else if (op == 0x6E) *r = a / b;
    else if (op == 0x6F) *r = ovf ? 0 : (uint32_t)(sa % sb);
    else *r = a % b;
    return WINT_OK;
}

static wint_status div64(uint8_t op, uint64_t a, uint64_t b, uint64_t* r) {
    if (b == 0) return WINT_T_DIV;
    int64_t sa = (int64_t)a, sb = (int64_t)b;
    int ovf = sa == INT64_MIN && sb == -1;
    if (op == 0x7F && ovf) return WINT_T_DIV;
    if (op == 0x7F) *r = (uint64_t)(sa / sb);
    else if (op == 0x80) *r = a / b;
    else if (op == 0x81) *r = ovf ? 0 : (uint64_t)(sa % sb);
    else *r = a % b;
    return WINT_OK;
}

static wint_status bin32(uint8_t op, uint32_t a, uint32_t b, uint64_t* r) {
    uint32_t s = b & 31;
    switch (op) {
    case 0x6A: *r = a + b; break;
    case 0x6B: *r = a - b; break;
    case 0x6C: *r = a * b; break;
    case 0x71: *r = a & b; break;
    case 0x72: *r = a | b; break;
    case 0x73: *r = a ^ b; break;
    case 0x74: *r = a << s; break;
    case 0x75: *r = (uint32_t)((int32_t)a >> s); break;
    case 0x76: *r = a >> s; break;
    case 0x77: *r = s ? (a << s | a >> (32 - s)) : a; break;
    case 0x78: *r = s ? (a >> s | a << (32 - s)) : a; break;
    default: return div32(op, a, b, r);
    }
    *r = (uint32_t)*r;
    return WINT_OK;
}

static wint_status bin64(uint8_t op, uint64_t a, uint64_t b, uint64_t* r) {
    uint64_t s = b & 63;
    switch (op) {
    case 0x7C: *r = a + b; break;
    case 0x7D: *r = a - b; break;
    case 0x7E: *r = a * b; break;
    case 0x83: *r = a & b; break;
    case 0x84: *r = a | b; break;
    case 0x85: *r = a ^ b; break;
    case 0x86: *r = a << s; break;
    case 0x87: *r = (uint64_t)((int64_t)a >> s); break;
    case 0x88: *r = a >> s; break;
    case 0x89: *r = s ? (a << s | a >> (64 - s)) : a; break;
    case 0x8A: *r = s ? (a >> s | a << (64 - s)) : a; break;
    default: return div64(op, a, b, r);
    }
    return WINT_OK;
}

wint_status wint_num(uint8_t op, uint64_t* st, uint32_t* sp) {
    int n = wint_num_arity(op);
    if (n == 0) return WINT_E_UNSUPPORTED;
    if (n == 1) return unary(op, &st[*sp - 1]);
    uint64_t a = st[*sp - 2], b = st[*sp - 1], r;
    wint_status s = WINT_OK;
    if (op <= 0x4F) r = cmp(op, (uint32_t)a, (uint32_t)b, 0);
    else if (op <= 0x5A) r = cmp(op, a, b, 1);
    else if (op <= 0x78) s = bin32(op, (uint32_t)a, (uint32_t)b, &r);
    else s = bin64(op, a, b, &r);
    if (s) return s;
    st[*sp - 2] = r;
    (*sp)--;
    return WINT_OK;
}
