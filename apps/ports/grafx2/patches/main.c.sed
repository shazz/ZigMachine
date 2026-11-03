# KESTREL: main() becomes grafx2_main(), called (and resumed) by kestrel_main.c
s/^int main(int argc,char \* argv\[\])$/int grafx2_main(int argc,char * argv[])/
# KESTREL: the floppy is read-only, so quitting saves no gfx2.cfg / gfx2.ini (a failed save is Error(),
# then exit(): the cart would trap instead of going back to the GEM desktop)
s/^    if (Config.Auto_save)$/    if (0 \&\& Config.Auto_save) \/* KESTREL: read-only floppy *\//
