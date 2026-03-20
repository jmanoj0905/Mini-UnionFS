/*
 * rw_ops.c — STUB: Write-side FUSE callbacks (Person 2's work)
 *
 * These are placeholder implementations so the project compiles.
 * Person 2 replaces this entire file with the real CoW engine.
 */

#include "unionfs.h"

/* Stub: no CoW yet */
int cow_copy(const char *path) {
    (void) path;
    return -ENOSYS;
}

/* Stub: no mkdir -p yet */
int make_parent_dirs(const char *full_path) {
    (void) full_path;
    return -ENOSYS;
}

/* Minimal open: just verify the file exists via resolve_path */
int unionfs_open(const char *path, struct fuse_file_info *fi) {
    (void) fi;
    char resolved[MAX_PATH_LEN];
    return resolve_path(path, resolved) < 0 ? -ENOENT : 0;
}

/* Stub: writes not supported yet */
int unionfs_write(const char *path, const char *buf, size_t size,
                  off_t offset, struct fuse_file_info *fi) {
    (void) path; (void) buf; (void) size; (void) offset; (void) fi;
    return -ENOSYS;
}

/* Stub: file creation not supported yet */
int unionfs_create(const char *path, mode_t mode,
                   struct fuse_file_info *fi) {
    (void) path; (void) mode; (void) fi;
    return -ENOSYS;
}

/* Stub: truncate not supported yet */
int unionfs_truncate(const char *path, off_t size,
                     struct fuse_file_info *fi) {
    (void) path; (void) size; (void) fi;
    return -ENOSYS;
}

/* Stub: timestamp update not supported yet */
int unionfs_utimens(const char *path, const struct timespec tv[2],
                    struct fuse_file_info *fi) {
    (void) path; (void) tv; (void) fi;
    return -ENOSYS;
}

/* Stub: release is a no-op (safe default) */
int unionfs_release(const char *path, struct fuse_file_info *fi) {
    (void) path; (void) fi;
    return 0;
}
