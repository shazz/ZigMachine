"""Turn upstream pt2_main.c (a blocking main loop) into the cart's two entry points.

main() becomes pt2_boot(): everything up to the main loop. The loop's body becomes pt2_frame(),
which kestrel_main.c's frame() calls once a VBL. Upstream stays untouched; this runs at build time
and fails loudly if upstream's loop changes shape."""
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
head = "\twhile (editor.programRunning)\n\t{\n"
tail = "\t}\n\n\tcleanUp();\n\tSDL_Quit();\n\n\treturn 0;\n}\n"
for needle in ("int main(int argc, char *argv[])\n", head, tail):
    if s.count(needle) != 1:
        sys.exit(f"split_main: upstream pt2_main.c changed shape, {needle!r} found {s.count(needle)} times")
s = s.replace("int main(int argc, char *argv[])\n", "int pt2_boot(int argc, char *argv[])\n")
s = s.replace(head, "\treturn 0;\n}\n\nvoid pt2_frame(void)\n{\n")
s = s.replace(tail, "}\n")
open(dst, "w").write(s)
