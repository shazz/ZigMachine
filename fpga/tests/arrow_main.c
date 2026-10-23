/* tests/test_cart_pointer.py: one cart's native objects linked with this main instead of host/main.c,
 * to ask the board firmware's question (cycles/bcursor.c) of the cart's generated tables: does
 * GEM's arrow go over it. Prints "arrow 0" or "arrow 1". */
#include <stdio.h>

#include "input_bridge.h"

int main(void) {
    printf("arrow %d\n", input_arrow());
    return 0;
}
