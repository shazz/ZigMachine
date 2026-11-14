# KESTREL: the PATH field's text goes through kestrel_cpath() ("/c" is C:, kestrel_cpath.c) before the chdir
s|strcpy(pathU, editor.currPath);|strcpy(pathU, editor.currPath); kestrel_cpath(pathU);|
