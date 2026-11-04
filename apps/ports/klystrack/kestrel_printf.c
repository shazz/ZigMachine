/* The labels klystron formats on every repaint (font_write_va, patches/font.c.sed): musl's vsnprintf costs
 * ~400 rv32 instructions a call through its FILE layer. This does the common conversions itself: %s %c %d %i
 * %u %x %X %%, the flags - 0 + and space, a width (digits or *), a precision on %s. A format with anything
 * else (a float, a length modifier, '#', a precision on a number, a negative * width, '0' on %s/%c) is
 * handed whole to musl before any argument is read, so the output is musl's in every case.
 *   kestrel_vsnprintf(buf, n, fmt, va)   as vsnprintf */
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

/* 1 when every conversion of fmt is one handled below. */
static int simple(const char *f)
{
    for (; *f; f++) {
        if (*f != '%') continue;
        f++;
        int zero = 0;
        for (; *f == '-' || *f == '0' || *f == '+' || *f == ' '; f++) zero |= *f == '0';
        if (*f == '*') f++;
        else while (*f >= '0' && *f <= '9') f++;
        int prec = *f == '.';
        if (prec) { f++; while (*f >= '0' && *f <= '9') f++; }
        switch (*f) {
        case 's': case 'c': if (zero) return 0; if (prec && *f == 'c') return 0; break;
        case 'd': case 'i': case 'u': case 'x': case 'X': if (prec) return 0; break;
        case '%': break;
        default: return 0;                          /* floats, length modifiers, '#', %p, %n, '.*', the end */
        }
    }
    return 1;
}

typedef struct { char *b; size_t n, len; } out_t;
static void put(out_t *o, char c) { if (o->len + 1 < o->n) o->b[o->len] = c; o->len++; }
static void pad(out_t *o, char c, int k) { while (k-- > 0) put(o, c); }

/* A number: digits of v (base 10 or 16), its sign, zero or space padding to the width, as C's printf. */
static void number(out_t *o, unsigned v, int neg, int base, int upper, int left, int zero, char sign, int width)
{
    char d[12]; int k = 0;
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    do { d[k++] = digits[v % (unsigned)base]; v /= (unsigned)base; } while (v);
    char s = neg ? '-' : sign;
    int len = k + (s != 0);
    if (!left && !zero) pad(o, ' ', width - len);
    if (s) put(o, s);
    if (!left && zero) pad(o, '0', width - len);
    while (k) put(o, d[--k]);
    if (left) pad(o, ' ', width - len);
}

/* One conversion at *pf (just past the '%'); returns the format just past it. */
static const char *convert(out_t *o, const char *f, va_list *va)
{
    int left = 0, zero = 0, width = 0, prec = -1; char sign = 0;
    for (; *f == '-' || *f == '0' || *f == '+' || *f == ' '; f++)
        if (*f == '-') left = 1; else if (*f == '0') zero = 1; else if (*f == '+') sign = '+'; else if (!sign) sign = ' ';
    if (*f == '*') { width = va_arg(*va, int); f++; }
    else while (*f >= '0' && *f <= '9') width = width * 10 + (*f++ - '0');
    if (*f == '.') { f++; prec = 0; while (*f >= '0' && *f <= '9') prec = prec * 10 + (*f++ - '0'); }
    if (left) zero = 0;
    switch (*f) {
    case 's': {
        const char *s = va_arg(*va, const char *);
        if (!s) s = "(null)";
        int len = (int)strlen(s);
        if (prec >= 0 && len > prec) len = prec;
        if (!left) pad(o, ' ', width - len);
        for (int i = 0; i < len; i++) put(o, s[i]);
        if (left) pad(o, ' ', width - len);
        break;
    }
    case 'c':
        if (!left) pad(o, ' ', width - 1);
        put(o, (char)va_arg(*va, int));
        if (left) pad(o, ' ', width - 1);
        break;
    case 'd': case 'i': {
        int v = va_arg(*va, int);
        number(o, v < 0 ? 0u - (unsigned)v : (unsigned)v, v < 0, 10, 0, left, zero, sign, width);
        break;
    }
    case 'u': number(o, va_arg(*va, unsigned), 0, 10, 0, left, zero, 0, width); break;
    case 'x': case 'X': number(o, va_arg(*va, unsigned), 0, 16, *f == 'X', left, zero, 0, width); break;
    default: put(o, '%'); break;                    /* "%%" */
    }
    return f + 1;
}

int kestrel_vsnprintf(char *b, size_t n, const char *fmt, va_list va)
{
    if (!simple(fmt)) return vsnprintf(b, n, fmt, va);
    for (const char *f = fmt; *f; f++) if (*f == '*') {   /* a negative * width: musl's (it means '-') */
        va_list c; va_copy(c, va);
        int w = 0, neg = 0;
        for (const char *g = fmt; *g; g++) {
            if (*g != '%') continue;
            g++;
            while (*g == '-' || *g == '0' || *g == '+' || *g == ' ') g++;
            if (*g == '*') { w = va_arg(c, int); neg |= w < 0; g++; }
            while ((*g >= '0' && *g <= '9') || *g == '.') g++;
            if (*g == 's') (void)va_arg(c, const char *);
            else if (*g != '%') (void)va_arg(c, int);
        }
        va_end(c);
        if (neg) return vsnprintf(b, n, fmt, va);
        break;
    }
    out_t o = { b, n, 0 };
    va_list v; va_copy(v, va);
    for (const char *f = fmt; *f;) {
        if (*f != '%') { put(&o, *f++); continue; }
        f = convert(&o, f + 1, &v);
    }
    va_end(v);
    if (n) b[o.len < n ? o.len : n - 1] = 0;
    return (int)o.len;
}
