/* Unpack SID-Wizard's native C64 program (resources/SID-Wizard.cmp, Hermit's compressor) to a plain .prg at
 * build time, as the PC version's decrunchC64code() does at start (upstream host/file.c). The cart then
 * copies the plain program in (upstream's UNCOMPRESSED_NATIVES path) and carries no decompressor.
 *   unpack <in.cmp> <out.prg> */
#include <stdio.h>
#include <stdlib.h>
#include "../upstream/native/sources/tools/decompressor.c"

int main(int argc, char **argv)
{
    static unsigned char in[0x10000], work[0x10001], out[0x20000];
    if (argc != 3) { fprintf(stderr, "usage: unpack in.cmp out.prg\n"); return 2; }
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    int n = (int)fread(in, 1, sizeof in, f);
    fclose(f);
    Compression_decompressorCopyData(in, n, work);
    int m = Compression_decompressData(work, n, out);
    if (m <= 2 || m > 0x10000) { fprintf(stderr, "unpack: bad size %d\n", m); return 1; }
    f = fopen(argv[2], "wb");
    if (!f || fwrite(out, 1, (size_t)m, f) != (size_t)m) { perror(argv[2]); return 1; }
    fclose(f);
    printf("unpack: %d -> %d bytes, first bytes %02X %02X\n", n, m, out[0], out[1]);
    return 0;
}
