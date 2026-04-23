/*
 * main.c — Entry point for Mini-UnionFS
 *
 * Validates command-line arguments, initializes global state,
 * and hands off to fuse_main().
 */

#include "unionfs.h"

static void usage(const char *progname) {
    fprintf(stderr, "Usage: %s <lower_dir> <upper_dir> <mount_dir>\n", progname);
    fprintf(stderr, "\n");
    fprintf(stderr, "  lower_dir   Read-only base image layer\n");
    fprintf(stderr, "  upper_dir   Read-write container layer\n");
    fprintf(stderr, "  mount_dir   FUSE mount point (unified view)\n");
}

static int is_directory(const char *path) {
    struct stat st;
    if (stat(path, &st) == -1) {
        return 0;
    }
    return S_ISDIR(st.st_mode);
}

int main(int argc, char *argv[]) {
    if (argc < 4) {
        usage(argv[0]);
        return 1;
    }

    /* --- Allocate and populate global state --- */
    struct mini_unionfs_state *state = malloc(sizeof(*state));
    //holds path for upper dir and lower dir
    if (!state) {
        perror("malloc");
        return 1;
    }

    state->lower_dir = realpath(argv[1], NULL);
    state->upper_dir = realpath(argv[2], NULL);

    if (!state->lower_dir) {
        fprintf(stderr, "Error: lower_dir '%s' does not exist\n", argv[1]);
        free(state);
        return 1;
    }
    if (!state->upper_dir) {
        fprintf(stderr, "Error: upper_dir '%s' does not exist\n", argv[2]);
        free(state->lower_dir);
        free(state);
        return 1;
    }
    if (!is_directory(state->lower_dir)) {
        fprintf(stderr, "Error: '%s' is not a directory\n", state->lower_dir);
        free(state->lower_dir);
        free(state->upper_dir);
        free(state);
        return 1;
    }
    if (!is_directory(state->upper_dir)) {
        fprintf(stderr, "Error: '%s' is not a directory\n", state->upper_dir);
        free(state->lower_dir);
        free(state->upper_dir);
        free(state);
        return 1;
    }

    fprintf(stderr, "Mini-UnionFS mounting...\n");
    fprintf(stderr, "  lower: %s\n", state->lower_dir);
    fprintf(stderr, "  upper: %s\n", state->upper_dir);
    fprintf(stderr, "  mount: %s\n", argv[3]);

    /*
     * Build FUSE argument vector.
     * -f = foreground mode (keeps stderr visible for debugging).
     * Remove -f for production / daemonized use.
     */
    char *fuse_argv[] = { argv[0], argv[3], NULL };
    int fuse_argc = 2;

    int ret = fuse_main(fuse_argc, fuse_argv, &unionfs_oper, state);

    /* --- Cleanup --- */
    free(state->lower_dir);
    free(state->upper_dir);
    free(state);
    return ret;
}
