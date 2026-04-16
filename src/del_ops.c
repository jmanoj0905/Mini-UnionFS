#include "unionfs.h"

/* * Helper: build_whiteout_for_path — Constructs the whiteout path 
 * for a given virtual path[cite: 5]. 
 */
static void build_whiteout_for_path(const char *upper_dir, const char *path, char *wh_out) {
    const char *basename_ptr = strrchr(path, '/');
    basename_ptr = basename_ptr ? basename_ptr + 1 : path;

    char dir_part[MAX_PATH_LEN];
    strncpy(dir_part, path, MAX_PATH_LEN);
    dir_part[MAX_PATH_LEN - 1] = '\0';
    char *last_slash = strrchr(dir_part, '/');
    
    if (last_slash && last_slash != dir_part) {
        *last_slash = '\0';
    } else {
        dir_part[0] = '\0'; // File is in root
    }

    if (dir_part[0] != '\0') {
        snprintf(wh_out, MAX_PATH_LEN, "%s%s/" WH_PREFIX "%s", upper_dir, dir_part, basename_ptr);
    } else {
        snprintf(wh_out, MAX_PATH_LEN, "%s/" WH_PREFIX "%s", upper_dir, basename_ptr);
    }
}

/* 3.1 — unionfs_unlink() — The Whiteout Engine */
int unionfs_unlink(const char *path) {
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper[MAX_PATH_LEN], lower[MAX_PATH_LEN], resolved[MAX_PATH_LEN];

    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    snprintf(lower, MAX_PATH_LEN, "%s%s", data->lower_dir, path);

    // Edge Case 4.1: Check if visible
    if (resolve_path(path, resolved) == -ENOENT) {
        return -ENOENT;
    }

    int in_upper = (access(upper, F_OK) == 0);
    int in_lower = (access(lower, F_OK) == 0);

    // PATH A: Exists ONLY in upper
    if (in_upper && !in_lower) {
        if (unlink(upper) == -1) return -errno;
        return 0;
    }

    // PATH B: Originates from lower_dir
    if (in_lower) {
        char wh_path[MAX_PATH_LEN];
        build_whiteout_for_path(data->upper_dir, path, wh_path);

        if (make_parent_dirs(wh_path) < 0) return -errno;

        // Create marker with 0000 permissions as system marker
        int fd = open(wh_path, O_CREAT | O_WRONLY | O_TRUNC, 0000);
        if (fd == -1) return -errno;
        close(fd);

        // Edge Case 4.2: If CoW copy exists, remove it
        if (in_upper) unlink(upper); 

        return 0;
    }

    return -ENOENT;
}

/* 3.2 — unionfs_mkdir() */
int unionfs_mkdir(const char *path, mode_t mode) {
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper[MAX_PATH_LEN], wh_check[MAX_PATH_LEN];

    // Edge Case 4.5: Remove stale whiteouts
    build_whiteout_for_path(data->upper_dir, path, wh_check);
    if (access(wh_check, F_OK) == 0) unlink(wh_check);

    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    if (make_parent_dirs(upper) < 0) return -errno;
    if (mkdir(upper, mode) == -1) return -errno;
    return 0;
}

/* 3.3 — unionfs_rmdir() */
int unionfs_rmdir(const char *path) {
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper[MAX_PATH_LEN], lower[MAX_PATH_LEN];

    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    snprintf(lower, MAX_PATH_LEN, "%s%s", data->lower_dir, path);

    if (access(upper, F_OK) == 0) {
        if (rmdir(upper) == -1) return -errno;
        // If it also exists in lower, we need a whiteout to hide it
        if (access(lower, F_OK) == 0) {
            char wh_path[MAX_PATH_LEN];
            build_whiteout_for_path(data->upper_dir, path, wh_path);
            int fd = open(wh_path, O_CREAT | O_WRONLY | O_TRUNC, 0000);
            if (fd != -1) close(fd);
        }
        return 0;
    }
    // Edge Case 4.4: Lower-only directory limitation
    if (access(lower, F_OK) == 0) return -EPERM;

    return -ENOENT;
}

/* 3.4 & 3.5 — Metadata ops with CoW */
int unionfs_chmod(const char *path, mode_t mode, struct fuse_file_info *fi) {
    (void) fi;
    char upper[MAX_PATH_LEN], lower[MAX_PATH_LEN];
    struct mini_unionfs_state *data = UNIONFS_DATA;
    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    snprintf(lower, MAX_PATH_LEN, "%s%s", data->lower_dir, path);

    if (access(upper, F_OK) != 0) {
        if (access(lower, F_OK) == 0) {
            int ret = cow_copy(path);
            if (ret < 0) return ret;
        } else return -ENOENT;
    }
    if (chmod(upper, mode) == -1) return -errno;
    return 0;
}

int unionfs_chown(const char *path, uid_t uid, gid_t gid, struct fuse_file_info *fi) {
    (void) fi;
    char upper[MAX_PATH_LEN], lower[MAX_PATH_LEN];
    struct mini_unionfs_state *data = UNIONFS_DATA;
    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    snprintf(lower, MAX_PATH_LEN, "%s%s", data->lower_dir, path);

    if (access(upper, F_OK) != 0) {
        if (access(lower, F_OK) == 0) {
            int ret = cow_copy(path);
            if (ret < 0) return ret;
        } else return -ENOENT;
    }
    if (lchown(upper, uid, gid) == -1) return -errno;
    return 0;
}

static int unionfs_statfs(const char *path, struct statvfs *stbuf) {
    (void) path;
    if (statvfs(UNIONFS_DATA->upper_dir, stbuf) == -1)
        return -errno;
    return 0;
}

int unionfs_symlink(const char *target, const char *linkpath) {
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper_link[MAX_PATH_LEN];

    snprintf(upper_link, MAX_PATH_LEN, "%s%s", data->upper_dir, linkpath);
    if (make_parent_dirs(upper_link) < 0) return -errno;
    if (symlink(target, upper_link) == -1) return -errno;
    return 0;
}

int unionfs_readlink(const char *path, char *buf, size_t size) {
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper[MAX_PATH_LEN], lower[MAX_PATH_LEN];
    char linkbuf[MAX_PATH_LEN];
    ssize_t len;

    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    snprintf(lower, MAX_PATH_LEN, "%s%s", data->lower_dir, path);

    if (access(upper, F_OK) == 0) {
        len = readlink(upper, linkbuf, size - 1);
    } else if (access(lower, F_OK) == 0) {
        len = readlink(lower, linkbuf, size - 1);
    } else {
        return -ENOENT;
    }

    if (len == -1) return -errno;
    linkbuf[len] = '\0';
    strncpy(buf, linkbuf, size - 1);
    buf[size - 1] = '\0';
    return 0;
}

/* 3.6 — FUSE Dispatch Table */
struct fuse_operations unionfs_oper = {
    .getattr    = unionfs_getattr,
    .readdir    = unionfs_readdir,
    .read       = unionfs_read,
    .open       = unionfs_open,
    .write      = unionfs_write,
    .create     = unionfs_create,
    .truncate   = unionfs_truncate,
    .utimens    = unionfs_utimens,
    .release    = unionfs_release,
    .unlink     = unionfs_unlink,
    .mkdir      = unionfs_mkdir,
    .rmdir      = unionfs_rmdir,
    .chmod      = unionfs_chmod,
    .chown      = unionfs_chown,
    .statfs     = unionfs_statfs,
    .symlink    = unionfs_symlink,
    .readlink   = unionfs_readlink,
};