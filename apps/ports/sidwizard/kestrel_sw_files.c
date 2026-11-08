/* The floppy and C: as SID-Wizard's disk drive (upstream host/file.c, included right after this by kestrel_sw.c,
 * calls these from patches/host__file.c.sed). Device 8 starts in the floppy's root ("/": the example song,
 * read-only); its file dialog shows C: (the SD card's /HD, or the page's ?c= image, read-write) as the folder "C",
 * where songs are saved, and C:'s root a ".." back. Device 9 is C: itself (sw_files_init). */

typedef struct { char *Name; unsigned char IsFile; unsigned char IsDir; } sw_direntry;   /* file.c's direntry */

/* fopen for a file only: the flat floppy answers a name with no '.' as a folder */
static FILE *sw_fopen_file(const char *name, const char *mode)
{
    FILE *f = fopen(name, mode);
    struct stat st;
    if (f && fstat(fileno(f), &st) == 0 && S_ISDIR(st.st_mode)) { fclose(f); return NULL; }
    return f;
}

static int sw_in_c_root(const char *cwd) { return !strcmp(cwd, "/C") || !strcmp(cwd, "/C/"); }

/* After readDir() listed the current folder: the floppy's root gets "C", C:'s root gets ".." */
static int sw_more_folders(void *list, int n)
{
    sw_direntry *d = list;
    char cwd[256];
    if (!getcwd(cwd, sizeof cwd) || n >= 2000 - 1) return n;
    const char *add = !strcmp(cwd, "/") && kestrel_c_mounted() ? "C" : sw_in_c_root(cwd) ? ".." : NULL;
    if (!add) return n;
    for (int i = 0; i < n; i++) if (!strcmp(d[i].Name, add)) return n;
    d[n].Name = strdup(add); d[n].IsFile = 0; d[n].IsDir = 1;
    return n + 1;
}

/* chdir, with ".." taken off the current path by hand (C:'s root goes back to the floppy) */
static int sw_chdir(const char *name)
{
    char cwd[256];
    if (strcmp(name, "..") || !getcwd(cwd, sizeof cwd)) return chdir(name);
    char *slash = strrchr(cwd, '/');
    if (!slash || slash == cwd) return chdir("/");
    *slash = 0;
    return chdir(cwd);
}
