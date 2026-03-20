/*
 * path.c — Path resolution and read-side FUSE callbacks
 *
 * Contains resolve_path() (the central lookup function), plus
 * getattr, readdir, and read.
 */

#include "unionfs.h"

/* ================================================================
 * resolve_path helpers
 * ================================================================ */

/*
 * Build the whiteout path for a given virtual path.
 * For "/subdir/file.txt" the whiteout is at upper_dir/subdir/.wh.file.txt
 */
static void build_whiteout_path(const char *upper_dir, const char *path,
                                char *wh_out, size_t wh_size) {
    const char *last_slash = strrchr(path, '/');

    if (last_slash && last_slash != path) {
        /* path has a directory component, e.g. "/subdir/file.txt" */
        size_t dir_len = (size_t)(last_slash - path);
        snprintf(wh_out, wh_size, "%s%.*s/" WH_PREFIX "%s",
                 upper_dir,
                 (int)dir_len, path,
                 last_slash + 1);
    } else if (last_slash == path) {
        /* path is "/file.txt" (directly in root) */
        snprintf(wh_out, wh_size, "%s/" WH_PREFIX "%s",
                 upper_dir, path + 1);
    } else {
        /* bare filename (shouldn't happen in FUSE, but handle it) */
        snprintf(wh_out, wh_size, "%s/" WH_PREFIX "%s",
                 upper_dir, path);
    }
}

/* ================================================================
 * resolve_path — the single most important function in the project
 * ================================================================ */

int resolve_path(const char *path, char *resolved_path) {
    struct mini_unionfs_state *data = UNIONFS_DATA;
    char upper[MAX_PATH_LEN];
    char lower[MAX_PATH_LEN];
    char whiteout[MAX_PATH_LEN];

    /* Root directory always exists — serve from upper */
    if (strcmp(path, "/") == 0) {
        strncpy(resolved_path, data->upper_dir, MAX_PATH_LEN);
        resolved_path[MAX_PATH_LEN - 1] = '\0';
        return 0;
    }

    /* Step 1: Check for whiteout marker */
    build_whiteout_path(data->upper_dir, path, whiteout, MAX_PATH_LEN);
    if (access(whiteout, F_OK) == 0)
        return -ENOENT;

    /* Step 2: Check upper layer */
    snprintf(upper, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    if (access(upper, F_OK) == 0) {
        strncpy(resolved_path, upper, MAX_PATH_LEN);
        resolved_path[MAX_PATH_LEN - 1] = '\0';
        return 0;
    }

    /* Step 3: Check lower layer */
    snprintf(lower, MAX_PATH_LEN, "%s%s", data->lower_dir, path);
    if (access(lower, F_OK) == 0) {
        strncpy(resolved_path, lower, MAX_PATH_LEN);
        resolved_path[MAX_PATH_LEN - 1] = '\0';
        return 0;
    }

    /* Step 4: Not found */
    return -ENOENT;
}

/* ================================================================
 * unionfs_getattr
 * ================================================================ */

int unionfs_getattr(const char *path, struct stat *stbuf,
                    struct fuse_file_info *fi) {
    (void) fi;
    memset(stbuf, 0, sizeof(struct stat));

    char resolved[MAX_PATH_LEN];
    int res = resolve_path(path, resolved);
    if (res < 0)
        return res;

    if (lstat(resolved, stbuf) == -1)
        return -errno;

    return 0;
}

/* ================================================================
 * unionfs_readdir — merges both layers, deduplicates, hides whiteouts
 * ================================================================ */

/* Simple linked-list string set for deduplication. */
struct seen_entry {
    char name[256];
    struct seen_entry *next;
};

static int seen_contains(struct seen_entry *head, const char *name) {
    for (struct seen_entry *cur = head; cur; cur = cur->next)
        if (strcmp(cur->name, name) == 0) return 1;
    return 0;
}

/* Returns new head (prepend pattern). Caller must reassign. */
static struct seen_entry *seen_add(struct seen_entry *head,
                                   const char *name) {
    struct seen_entry *entry = malloc(sizeof(struct seen_entry));
    if (!entry) return head;   /* OOM: skip silently */
    strncpy(entry->name, name, 255);
    entry->name[255] = '\0';
    entry->next = head;
    return entry;
}

static void seen_free(struct seen_entry *head) {
    struct seen_entry *cur = head;
    while (cur) {
        struct seen_entry *next = cur->next;
        free(cur);
        cur = next;
    }
}

/* Check if a whiteout exists for 'name' inside 'dir_path' under upper_dir. */
static int has_whiteout(const char *upper_dir, const char *dir_path,
                        const char *name) {
    char wh[MAX_PATH_LEN];
    if (strcmp(dir_path, "/") == 0)
        snprintf(wh, MAX_PATH_LEN, "%s/" WH_PREFIX "%s", upper_dir, name);
    else
        snprintf(wh, MAX_PATH_LEN, "%s%s/" WH_PREFIX "%s",
                 upper_dir, dir_path, name);
    return (access(wh, F_OK) == 0);
}

int unionfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                    off_t offset, struct fuse_file_info *fi,
                    enum fuse_readdir_flags flags) {
    (void) offset;
    (void) fi;
    (void) flags;

    struct mini_unionfs_state *data = UNIONFS_DATA;
    char dir_path[MAX_PATH_LEN];
    DIR *dp;
    struct dirent *de;

    /* seen is LOCAL — a fresh set for every readdir call.
     * Never make this a global: concurrent calls would corrupt it. */
    struct seen_entry *seen = NULL;

    filler(buf, ".", NULL, 0, 0);
    filler(buf, "..", NULL, 0, 0);
    seen = seen_add(seen, ".");
    seen = seen_add(seen, "..");

    /* --- Pass 1: Upper layer (takes precedence) --- */
    snprintf(dir_path, MAX_PATH_LEN, "%s%s", data->upper_dir, path);
    dp = opendir(dir_path);
    if (dp) {
        while ((de = readdir(dp)) != NULL) {
            const char *name = de->d_name;

            if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0)
                continue;
            /* Hide whiteout markers from directory listings */
            if (strncmp(name, WH_PREFIX, WH_PREFIX_LEN) == 0)
                continue;
            if (!seen_contains(seen, name)) {
                filler(buf, name, NULL, 0, 0);
                seen = seen_add(seen, name);
            }
        }
        closedir(dp);
    }

    /* --- Pass 2: Lower layer (fill gaps, skip whited-out entries) --- */
    snprintf(dir_path, MAX_PATH_LEN, "%s%s", data->lower_dir, path);
    dp = opendir(dir_path);
    if (dp) {
        while ((de = readdir(dp)) != NULL) {
            const char *name = de->d_name;

            if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0)
                continue;
            if (seen_contains(seen, name))
                continue;
            if (has_whiteout(data->upper_dir, path, name))
                continue;

            filler(buf, name, NULL, 0, 0);
            seen = seen_add(seen, name);
        }
        closedir(dp);
    }

    seen_free(seen);
    return 0;
}

/* ================================================================
 * unionfs_read
 * ================================================================ */

int unionfs_read(const char *path, char *buf, size_t size,
                 off_t offset, struct fuse_file_info *fi) {
    (void) fi;

    char resolved[MAX_PATH_LEN];
    int res = resolve_path(path, resolved);
    if (res < 0)
        return res;

    int fd = open(resolved, O_RDONLY);
    if (fd == -1)
        return -errno;

    int bytes_read = pread(fd, buf, size, offset);
    if (bytes_read == -1)
        bytes_read = -errno;

    close(fd);
    return bytes_read;
}
