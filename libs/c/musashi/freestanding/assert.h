// Freestanding stand-in for <assert.h>. Musashi asserts only on host-side
// programming errors (bad CPU type, bad register id); there is no abort() to
// call in wasm32-freestanding and nothing to print to, so they compile away.
#ifndef ZM_FREESTANDING_ASSERT_H
#define ZM_FREESTANDING_ASSERT_H

#define assert(expr) ((void)0)

#endif
