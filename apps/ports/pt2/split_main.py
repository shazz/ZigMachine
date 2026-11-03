"""Turn upstream pt2_main.c (a blocking main loop) into the cart's two entry points.

main() becomes pt2_boot(): everything up to the main loop. The loop's body becomes pt2_frame(),
which kestrel_main.c's frame() calls once a VBL. Upstream stays untouched; this runs at build time
and fails loudly if upstream's loop changes shape."""
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
head = "\twhile (editor.programRunning)\n\t{\n"
tail = "\t}\n\n\tcleanUp();\n\tSDL_Quit();\n\n\treturn 0;\n}\n"
# KESTREL's "REALLY QUIT ?" (kestrel_port.h): askBox() is a modal loop that never returns on a cart.
CONFIRM = """
int kestrel_confirm_quit(void)
{
\tstatic uint64_t armedAt;
\tstatic bool armed;
\tconst uint64_t now = SDL_GetPerformanceCounter(); // microseconds (kestrel_sdl.c)

\tif (armed && now - armedAt < 3000000)
\t\treturn true;

\tarmed = true;
\tarmedAt = now;
\tdisplayMsg("PRESS AGAIN: QUIT");
\treturn false;
}
"""
for needle in ("int main(int argc, char *argv[])\n", head, tail):
    if s.count(needle) != 1:
        sys.exit(f"split_main: upstream pt2_main.c changed shape, {needle!r} found {s.count(needle)} times")
s = s.replace("int main(int argc, char *argv[])\n", "int pt2_boot(int argc, char *argv[])\n")
s = s.replace(head, "\treturn 0;\n}\n\nvoid pt2_frame(void)\n{\n")
# The loop's own condition, lost with the loop: once pt2 stops running, the cart quits back to the desktop.
s = s.replace(tail, "\tif (!editor.programRunning)\n\t\tkestrel_quit();\n}\n" + CONFIRM)
open(dst, "w").write(s)
