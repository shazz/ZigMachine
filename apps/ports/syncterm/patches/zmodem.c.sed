# A download is received into a NEW file: C: writes a file whole (Fcreate, saved at fclose) and refuses to open
# one to append ("ab" on a file that exists: ENOTSUP, docs/os/KOS_GEMDOS.md section 7). Upstream opens "ab" so a half-received
# file can be resumed from its end; here it starts over from byte 0 (start_bytes is the new file's length, 0).
s/fopen(fpath, "ab")/fopen(fpath, "wb")/
