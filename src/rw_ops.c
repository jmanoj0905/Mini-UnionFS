/*
 * rw_ops.c — Write-side FUSE callbacks & Copy-on-Write engine
 */

#include "unionfs.h"

/* 64 KB copy buffer as specified */
#define COW_BUF_SIZE (64 * 1024)

/* mkdir -p helper */
int make_parent_dirs(const char *full_path) {
    char tmp[MAX_PATH_LEN];
    strncpy(tmp, full_path, MAX_PATH_LEN);
    tmp[MAX_PATH_LEN - 1] = '\0';

    char *last_slash = strrchr(tmp, '/');
    if (!last_slash || last_slash == tmp) return 0;

    for (char *p = tmp + 1; p < last_slash; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0755) == -1 && errno != EEXIST) return -errno;
            *p = '/';
        }
    }

    *last_slash = '\0';
    if (mkdir(tmp, 0755) == -1 && errno != EEXIST) return -errno;
    return 0;
}

/* Copy-on-Write engine */
int cow_copy(const char *path) {
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char src[MAX_PATH_LEN], dst[MAX_PATH_LEN];

    snprintf(src, MAX_PATH_LEN, "%s%s", data->lower_dir, path);
    snprintf(dst, MAX_PATH_LEN, "%s%s", data->upper_dir, path);

    int src_fd = open(src, O_RDONLY);
    if (src_fd == -1) return -errno;

    struct stat st;
    if (fstat(src_fd, &st) == -1) {
        close(src_fd);
        return -errno;
    }

    if (make_parent_dirs(dst) < 0) {
        close(src_fd);
        return -errno;
    }

    int dst_fd = open(dst, O_CREAT | O_WRONLY | O_TRUNC, st.st_mode);
    if (dst_fd == -1) {
        close(src_fd);
        return -errno;
    }

    char buf[COW_BUF_SIZE];
    ssize_t bytes;
    while ((bytes = read(src_fd, buf, COW_BUF_SIZE)) > 0) {
        ssize_t written = 0;
        while (written < bytes) {
            ssize_t w = write(dst_fd, buf + written, bytes - written);
            if (w == -1) {
                close(src_fd); close(dst_fd);
                return -errno;
            }
            written += w;
        }
    }
    
    fchmod(dst_fd, st.st_mode); 
    close(src_fd);
    close(dst_fd);
    return 0;
}

int unionfs_open(const char *path, struct fuse_file_info *fi) {
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper[MAX_PATH_LEN], lower[MAX_PATH_LEN], resolved[MAX_PATH_LEN];

    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    snprintf(lower, MAX_PATH_LEN, "%s%s", data->lower_dir, path);

    if ((fi->flags & O_ACCMODE) != O_RDONLY) {
        if (access(upper, F_OK) != 0) {
            if (access(lower, F_OK) == 0) {
                int ret = cow_copy(path);
                if (ret < 0) return ret;
            }
        }
    }
    return resolve_path(path, resolved);
}

int unionfs_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    (void) fi;
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper[MAX_PATH_LEN];

    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    int fd = open(upper, O_WRONLY);
    if (fd == -1) return -errno;

    ssize_t res = pwrite(fd, buf, size, offset);
    if (res == -1) res = -errno;

    close(fd);
    return (int)res;
}

int unionfs_create(const char *path, mode_t mode, struct fuse_file_info *fi) {
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper[MAX_PATH_LEN];

    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    if (make_parent_dirs(upper) < 0) return -errno;

    int fd = open(upper, O_CREAT | O_WRONLY | O_TRUNC, mode);
    if (fd == -1) return -errno;

    fi->fh = (uint64_t)fd;
    return 0;
}

int unionfs_truncate(const char *path, off_t size, struct fuse_file_info *fi) {
    (void) fi;
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper[MAX_PATH_LEN], lower[MAX_PATH_LEN];

    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    snprintf(lower, MAX_PATH_LEN, "%s%s", data->lower_dir, path);

    if (access(upper, F_OK) != 0) {
        if (access(lower, F_OK) == 0) {
            int ret = cow_copy(path);
            if (ret < 0) return ret;
        } else {
            return -ENOENT;
        }
    }

    if (truncate(upper, size) == -1) return -errno;
    return 0;
}

int unionfs_utimens(const char *path, const struct timespec tv[2], struct fuse_file_info *fi) {
    (void) fi;
    char resolved[MAX_PATH_LEN];
    if (resolve_path(path, resolved) < 0) return -ENOENT;

    if (utimensat(AT_FDCWD, resolved, tv, AT_SYMLINK_NOFOLLOW) == -1)
        return -errno;
    return 0;
}

int unionfs_release(const char *path, struct fuse_file_info *fi) {
    (void) path;
    if (fi->fh) {
        close((int)fi->fh);
        fi->fh = 0;
    }
    return 0;
}