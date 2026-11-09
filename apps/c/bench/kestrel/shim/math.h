/* sin/cos/exp/log (double) come from the toolchain's compiler_rt; atan and every single-precision function
 * are fmath.c's (f32 operations only, so the "single" builds really are single). */
#ifndef KS_MATH_H
#define KS_MATH_H
double sin(double), cos(double), atan(double), exp(double), log(double);
float bsinf(float), bcosf(float), batanf(float), bexpf(float), blogf(float);
#define sqrt __builtin_sqrt
#define sqrtf __builtin_sqrtf
#define fabs __builtin_fabs
#define fabsf __builtin_fabsf
#endif
