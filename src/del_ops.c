/*
 * del_ops.c — STUB: Deletion & directory FUSE callbacks (Person 3's work)
 *
 * These are placeholder implementations so the project compiles.
 * Person 3 replaces this entire file with the real deletion engine.
 *
 * Also contains the fuse_operations dispatch table (assembled here
 * because it references every callback across all files).
 */

#include "unionfs.h"

/* Stub: unlink not supported yet */
int unionfs_unlink(const char *path) {
    (void) path;
    return -ENOSYS;
}

/* Stub: mkdir not supported yet */
int unionfs_mkdir(const char *path, mode_t mode) {
    (void) path; (void) mode;
    return -ENOSYS;
}

/* Stub: rmdir not supported yet */
int unionfs_rmdir(const char *path) {
    (void) path;
    return -ENOSYS;
}

/* Stub: chmod not supported yet */
int unionfs_chmod(const char *path, mode_t mode, struct fuse_file_info *fi) {
    (void) path; (void) mode; (void) fi;
    return -ENOSYS;
}

/* Stub: chown not supported yet */
int unionfs_chown(const char *path, uid_t uid, gid_t gid,
                  struct fuse_file_info *fi) {
    (void) path; (void) uid; (void) gid; (void) fi;
    return -ENOSYS;
}

/* ================================================================
 * FUSE operations dispatch table
 *
 * This is the single struct that maps syscall names to our callbacks.
 * Every person's functions are wired in here.
 * ================================================================ */

struct fuse_operations unionfs_oper = {
    /* Person 1 — read path (path.c) */
    .getattr  = unionfs_getattr,
    .readdir  = unionfs_readdir,
    .read     = unionfs_read,

    /* Person 2 — write path (rw_ops.c) */
    .open     = unionfs_open,
    .write    = unionfs_write,
    .create   = unionfs_create,
    .truncate = unionfs_truncate,
    .utimens  = unionfs_utimens,
    .release  = unionfs_release,

    /* Person 3 — deletion & directory ops (del_ops.c) */
    .unlink   = unionfs_unlink,
    .mkdir    = unionfs_mkdir,
    .rmdir    = unionfs_rmdir,
    .chmod    = unionfs_chmod,
    .chown    = unionfs_chown,
};
