/* What klystrack links against that the cart does not have. */
#include <pwd.h>
#include <stddef.h>

/* toolutil.c expand_tilde(): no password database on the cart, so "~" never expands (no path uses it here). */
struct passwd *getpwuid(uid_t uid) { (void)uid; return NULL; }
