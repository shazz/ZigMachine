# KESTREL: "/C" (the card's HD, docs/KOS_GEMDOS.md §5) is a folder at "/" when C: mounts: the file browser lists it
/^  \*entryCount = count;$/i\
  if (strcmp(path, "/") == 0 \&\& kestrel_c_mounted() \&\& count < capacity) { strcpy(entries[count].name, "C"); entries[count].isDirectory = 1; count++; }
