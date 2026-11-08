# The machine's two disks (kestrel_sw_files.c): a name with no '.' on the flat floppy reads as a folder, so a file
# open checks it got a file ("@swconfig" is not there); the floppy's root lists C: as folder "C" and C:'s root a
# ".." back (the dialog's folders, CHDIR); ".." goes up a level by name (libc does not fold it).
s|^   fp=fopen(FileNamePtr,Operation);|   fp=sw_fopen_file(FileNamePtr,Operation); /* kestrel */|
s|^ closedir(Directory); //printf("readcloseddir %s %d\\n",extension,FileAmount);| closedir(Directory); FileAmount = sw_more_folders(dirlist, FileAmount); /* kestrel */|
s|^     chdir(dirlist\[FolderValues\[i\]\].Name);|     sw_chdir(dirlist[FolderValues[i]].Name); /* kestrel */|
# FAT names are upper case (the floppy, C:): the dialog's extension filter (".swm") matches them either case.
s/|| !strcmp(extension,filExt((byte\*)DirEntry->d_name)) ) { \/\/printf/|| !strcasecmp(extension,filExt((byte*)DirEntry->d_name)) ) { \/* kestrel *\/ \/\/printf/
