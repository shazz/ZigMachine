// Freestanding stand-in for <math.h>, for Musashi's m68kfpu.c.
//
// m68kcpu.c includes m68kfpu.c unconditionally, and the generated opcode table
// carries the 68881/68882 handlers whatever CPU type is selected — so the FPU
// code must LINK even though a 68000 can never reach it. Only declarations live
// here; the definitions are in fpu_stubs.c, which traps if one is ever called.
#ifndef ZM_FREESTANDING_MATH_H
#define ZM_FREESTANDING_MATH_H

extern double floor(double x);
extern double ceil(double x);
extern double fabs(double x);
extern double sqrt(double x);
extern double log(double x);
extern double log10(double x);
extern double log2(double x);
extern double exp(double x);
extern double pow(double x, double y);
extern double fmod(double x, double y);
extern double sin(double x);
extern double cos(double x);
extern double tan(double x);
extern double asin(double x);
extern double acos(double x);
extern double atan(double x);
extern double sinh(double x);
extern double cosh(double x);
extern double tanh(double x);
extern double atanh(double x);
extern double expm1(double x);
extern double log1p(double x);
extern double modf(double x, double *ipart);
extern double ldexp(double x, int e);
extern double frexp(double x, int *e);

#endif
