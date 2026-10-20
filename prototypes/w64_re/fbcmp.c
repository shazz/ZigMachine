/* fbcmp W64.bin W32.bin: which source word each written word of a W64 picture holds, against a W32
 * picture of the same static frame, counted over beat pairs whose W32 words 2 and 3 differ
 * (pixels within a pair are otherwise often doubled, which hides the lane). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
    FILE *fa = fopen(argv[1], "rb"), *fb = fopen(argv[2], "rb");
    static uint32_t a[800 * 280], b[800 * 280];
    size_t n = fread(a, 4, 800 * 280, fa); fread(b, 4, 800 * 280, fb);
    unsigned px = 0, pairs = 0, w0 = 0, w0_1 = 0, w3 = 0, w3_2 = 0, all = 0, alleq = 0;
    for (size_t i = 0; i < n; i++) px += a[i] == b[i];
    for (size_t i = 0; i + 3 < n; i += 4) {
        all++; alleq += a[i] == b[i] && a[i + 3] == b[i + 3];
        if (b[i + 2] == b[i + 3] || b[i] == b[i + 1]) continue;
        pairs++; w0 += a[i] == b[i]; w0_1 += a[i] == b[i + 1]; w3 += a[i + 3] == b[i + 3]; w3_2 += a[i + 3] == b[i + 2];
    }
    printf("pairs with distinct words %u: w0==src0 %u w0==src1 %u | w3==src3 %u w3==src2 %u ; all pairs %u, w0&w3 exact %u; pixels equal %u of %u\n",
           pairs, w0, w0_1, w3, w3_2, all, alleq, px, (unsigned)n);
    return 0;
}
