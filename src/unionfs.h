/*
 * unionfs.h — Shared header for Mini-UnionFS
 *
 * Defines the global state, constants, and function declarations
 * used by all source files. This is the interface contract between
 * all team members.
 */

#ifndef UNIONFS_H
#define UNIONFS_H

#define FUSE_USE_VERSION 31

#include <fuse.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h> //file controls
#include <unistd.h> // Posix System calls // low level os ops
#include <sys/stat.h> //File perms st.s
#include <sys/types.h> //datatype for sys calls
#include <dirent.h> //dir handling
#include <limits.h> //path lim

/* ---------- Constants ---------- */
#define WH_PREFIX     ".wh."      /* whiteout file prefix */
#define WH_PREFIX_LEN 4
#define MAX_PATH_LEN  PATH_MAX

/* ---------- Global State ---------- */
struct mini_unionfs_state {
    char *lower_dir;
    char *upper_dir;
};

#define UNIONFS_DATA ((struct mini_unionfs_state *) fuse_get_context()->private_data)

/* ---------- Person 1 exports (path.c) ---------- */

int resolve_path(const char *path, char *resolved_path);

/* FUSE callbacks: read path */
int unionfs_getattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi);
int unionfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info *fi, enum fuse_readdir_flags flags);
int unionfs_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi);

/* ---------- Person 2 exports (rw_ops.c) ---------- */

int cow_copy(const char *path);
int make_parent_dirs(const char *full_path);

/* FUSE callbacks: write path */
int unionfs_open(const char *path, struct fuse_file_info *fi);
int unionfs_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi);
int unionfs_create(const char *path, mode_t mode, struct fuse_file_info *fi);
int unionfs_truncate(const char *path, off_t size, struct fuse_file_info *fi);
int unionfs_utimens(const char *path, const struct timespec tv[2], struct fuse_file_info *fi);
int unionfs_release(const char *path, struct fuse_file_info *fi);

/* ---------- Person 3 exports (del_ops.c) ---------- */

/* FUSE callbacks: deletion & directory ops */
int unionfs_unlink(const char *path);
int unionfs_mkdir(const char *path, mode_t mode);
int unionfs_rmdir(const char *path);
int unionfs_chmod(const char *path, mode_t mode, struct fuse_file_info *fi);
int unionfs_chown(const char *path, uid_t uid, gid_t gid, struct fuse_file_info *fi);

/* ---------- Dispatch table (assembled in del_ops.c) ---------- */
extern struct fuse_operations unionfs_oper;

#endif /* UNIONFS_H */
