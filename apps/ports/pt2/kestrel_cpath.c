/* pt2's PATH field types its letters in lower case (pt2_textedit.c, handleTextEditInputChar), and wasi-libc
 * finds a preopen by its exact name: "/c/mods" is not C: ("/C"), so it falls to the floppy, whose flat FS
 * lists its root for any folder. A leading "/c" is C: here, before the path is chdir'd (kestrel_port.h;
 * patches/pt2_textedit.c.sed). GEMDOS takes the rest in any case. */
#include <ctype.h>

void kestrel_cpath(char *path)
{
    if (path[0] == '/' && tolower((unsigned char)path[1]) == 'c' && (path[2] == '/' || path[2] == '\0'))
        path[1] = 'C';
}
