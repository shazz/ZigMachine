/* pvmp3's one build define (AOSP Android.bp cflags), as a forced include: a "(x)" in a make variable
 * would reach the shell unquoted. */
#define OSCL_UNUSED_ARG(x) (void)(x)
