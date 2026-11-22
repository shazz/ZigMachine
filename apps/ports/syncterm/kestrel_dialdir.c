/* SyncTERM's dialing directory on C: (KOS GEMDOS, "/C" = the card's HD, docs/KOS_GEMDOS.md §5).
 *
 * kestrel_main.c starts SyncTERM with no URL and with -n / -b (upstream's own overrides of
 * get_syncterm_filename) naming C:\SYNCTERM\SYNCTERM.INI and C:\SYNCTERM\SYNCTERM.LST, so the directory
 * opens and every entry added or edited is saved there. Upstream's other paths (XDG cache, downloads)
 * fall on the read-only floppy and fail as SyncTERM expects a missing folder to.
 *
 * kestrel_dialdir_seed() runs once settings are loaded (patches/syncterm.c.sed, before the directory
 * loop): with no list on C: yet, it writes one, an entry per telnet:// or rlogin:// line of the floppy's
 * DIAL.TXT plus the in-cart BBS (fakebbs.zig, which answers with or without a ZIGNIC card), through
 * SyncTERM's own parse_url and add_bbs, so the file is exactly what its reader reads.
 *
 * kestrel_rewrite(): C: writes a file whole (Fcreate, saved at fclose) and refuses "r+" (in place), so
 * the three places upstream updates the list in place (patches/*.sed) read it "rb" and call this to
 * write it again "wb". */
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include "kestrel_dialdir.h"
#include "bbslist.h"
#include "syncterm.h"
#include "conn.h"

void kestrel_log(const char *m);
int kestrel_c_mounted(void); /* ../kestrel_sdl2/src/opt/kestrel_wasi_c.c */

static void download_ready(void)   /* C:\DOWNLOAD, made once, the first time a list entry names it */
{
    static int done;
    struct stat st;
    if (done) return;
    done = 1;
    if (stat(KESTREL_DOWNLOAD, &st) == 0 && S_ISDIR(st.st_mode)) return;
    if (mkdir(KESTREL_DOWNLOAD, 0777) != 0) kestrel_log("syncterm: no " KESTREL_DOWNLOAD " on C:");
}

void kestrel_dldir(char *dldir, size_t size)
{
    if (!kestrel_c_mounted()) return;   /* no C:, nowhere to put a download: upstream's path fails as it did */
    if (strncmp(dldir, "/C/", 3) != 0) snprintf(dldir, size, "%s", KESTREL_DOWNLOAD);
    if (strcmp(dldir, KESTREL_DOWNLOAD) == 0) download_ready();
}

int kestrel_dialdir_ready(void)
{
    if (!kestrel_c_mounted()) return 0;
    struct stat st;
    if (mkdir(KESTREL_DIALDIR, 0777) != 0 && (stat(KESTREL_DIALDIR, &st) != 0 || !S_ISDIR(st.st_mode))) {
        kestrel_log("syncterm: no " KESTREL_DIALDIR " on C:");
        return 0;
    }
    return 1;
}

static void seed_one(const char *url, int *n)
{
    struct bbslist bbs;
    char u[LIST_ADDR_MAX + 16];
    snprintf(u, sizeof u, "%s", url);
    memset(&bbs, 0, sizeof bbs);
    parse_url(u, &bbs, CONN_TYPE_TELNET, true);
    if (!bbs.addr[0]) return;
    add_bbs(settings.list_path, &bbs, true);
    (*n)++;
}

void kestrel_dialdir_seed(void)
{
    if (strncmp(settings.list_path, "/C/", 3) != 0) return; /* not ours: the -b override was not given */
    FILE *f = fopen(settings.list_path, "rb");
    if (f) { fclose(f); return; }
    int n = 0;
    FILE *dial = fopen("/DIAL.TXT", "rb");
    if (dial) {
        char line[LIST_ADDR_MAX + 16];
        while (fgets(line, sizeof line, dial)) {
            line[strcspn(line, "\r\n")] = 0;
            if (strncmp(line, "telnet://", 9) == 0 || strncmp(line, "rlogin://", 9) == 0) seed_one(line, &n);
        }
        fclose(dial);
    }
    seed_one("telnet://" KESTREL_FAKEBBS, &n);
    char msg[96];
    snprintf(msg, sizeof msg, "syncterm: seeded %s with %d entries", settings.list_path, n);
    kestrel_log(msg);
}

FILE *kestrel_rewrite(FILE *fp, const char *path)
{
    static char sink[4096]; /* where the write goes when C: refuses it: SyncTERM's write fails quietly, as upstream's */
    if (fp) fclose(fp);
    FILE *w = fopen(path, "wb");
    if (w) return w;
    kestrel_log("syncterm: the list could not be written");
    return fmemopen(sink, sizeof sink, "w");
}
