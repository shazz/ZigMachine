# KESTREL: "/C" (the card's HD, docs/KOS_GEMDOS.md §5) is a folder at the floppy's root when C: mounts (kestrel_port.h)
/^\tclosedir(dir);$/i\
\tif (strcmp(data.fullpath, "/") == 0 \&\& kestrel_c_mounted()) add_file(FB_DIRECTORY, "C");
