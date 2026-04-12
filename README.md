# Mini-UnionFS

A userspace union filesystem built with FUSE (libfuse3). Replicates the core layering mechanism Docker uses to build container images: a read-only **lower layer** stacked under a read-write **upper layer**, presented as a single merged mount point.

## How It Works

```
mount_dir/          <-- unified view (what the user sees)
  ├── file_a.txt    <-- from upper_dir (takes precedence)
  └── file_b.txt    <-- from lower_dir (read-only base)

upper_dir/          <-- read-write container layer
lower_dir/          <-- read-only base image layer
```

Three core mechanisms make this possible:

**Path resolution** — every filesystem call resolves a virtual path through a priority chain: check for a whiteout marker in upper, then check upper, then check lower, then return ENOENT.

**Copy-on-Write** — writing to a file that only exists in the lower layer triggers a full copy to the upper layer first. The lower layer is never modified.

**Whiteout files** — deleting a lower-layer file creates a hidden `.wh.<filename>` marker in the upper layer. The path resolver sees this marker and reports the file as deleted, without touching the lower layer.

## Prerequisites

- Ubuntu 22.04 LTS (or compatible Linux)
- `libfuse3-dev` (FUSE 3.x development headers and library)
- GCC with C11 support
- `pkg-config`

```bash
sudo apt-get install libfuse3-dev gcc make pkg-config
```

## Build

```bash
make
```

This produces the `mini_unionfs` binary in the project root.

To clean build artifacts:

```bash
make clean
```

## Usage

```bash
./mini_unionfs <lower_dir> <upper_dir> <mount_dir>
```

All three directories must already exist. Example:

```bash
mkdir -p /tmp/lower /tmp/upper /tmp/mount

# Populate the base image layer
echo "base config" > /tmp/lower/config.txt
echo "base data"   > /tmp/lower/data.txt

# Mount the union filesystem
./mini_unionfs /tmp/lower /tmp/upper /tmp/mount

# In another terminal:
cat /tmp/mount/config.txt               # reads from lower
echo "modified" > /tmp/mount/config.txt # CoW: copies to upper, writes there
rm /tmp/mount/data.txt                  # creates /tmp/upper/.wh.data.txt
```

To unmount:

```bash
fusermount3 -u /tmp/mount
```

## Testing

All tests live in the `testing/` directory. Run the full suite with:

```bash
bash testing/run_all_tests.sh
```

The suite mounts and unmounts the filesystem for each test in an isolated temporary directory, then cleans up. Each test prints `[PASS]` / `[FAIL]` per assertion and a per-script result.

### Test cases

| # | File | What it covers |
|---|------|----------------|
| 01 | `test_01_layer_visibility.sh` | Files from lower and upper visible through mount; upper shadows lower for same filename |
| 02 | `test_02_cow_write.sh` | Copy-on-Write on write, append, overwrite, and truncate; lower layer never modified |
| 03 | `test_03_whiteout.sh` | Deleting a lower file creates `.wh.` marker; deleting an upper-only file does not |
| 04 | `test_04_readdir_merge.sh` | Directory listing merges both layers, deduplicates, hides whiteout markers |
| 05 | `test_05_create_new_file.sh` | New files created through mount land in upper only |
| 06 | `test_06_nested_paths.sh` | Subdirectory visibility, CoW, and whiteout for nested paths |
| 07 | `test_07_directory_ops.sh` | `mkdir` goes to upper; `rmdir` upper-only succeeds; `rmdir` lower-only returns EPERM |
| 08 | `test_08_recreate_after_whiteout.sh` | Re-creating a deleted file clears the stale whiteout marker |
| 09 | `test_09_negative_cases.sh` | ENOENT on missing and whited-out paths; empty file reads; missing parent dir writes |

## Project Structure

```
.
├── Makefile
├── src/
│   ├── unionfs.h      # Shared header: state struct, constants, all declarations
│   ├── main.c         # Entry point: arg validation, realpath, fuse_main
│   ├── path.c         # Path resolution, getattr, readdir, read
│   ├── rw_ops.c       # Write path: open, write, create, truncate, CoW engine
│   └── del_ops.c      # Deletion: unlink, mkdir, rmdir + dispatch table
├── testing/
│   ├── run_all_tests.sh   # Test suite runner
│   ├── lib.sh             # Shared test utilities (setup, assertions, mount helpers)
│   ├── test_01_layer_visibility.sh
│   ├── test_02_cow_write.sh
│   ├── test_03_whiteout.sh
│   ├── test_04_readdir_merge.sh
│   ├── test_05_create_new_file.sh
│   ├── test_06_nested_paths.sh
│   ├── test_07_directory_ops.sh
│   ├── test_08_recreate_after_whiteout.sh
│   └── test_09_negative_cases.sh
│   └── test_unionfs.sh    # Original 3-scenario test
```

## Architecture

The FUSE operations dispatch table (`struct fuse_operations`) lives in `del_ops.c` and wires every callback to its implementation across the three operation files. Global state (paths to lower_dir and upper_dir) is stored in a `mini_unionfs_state` struct passed through `fuse_get_context()->private_data`.

Key design decisions:
- `readdir` does a two-pass merge (upper first, then lower) with a seen-set to deduplicate entries and suppress whiteout targets
- Open-mode detection uses `(fi->flags & O_ACCMODE) != O_RDONLY` to correctly catch both `O_WRONLY` and `O_RDWR` (since `O_RDONLY == 0`, a naive bitwise AND fails)
- CoW copies preserve the full directory tree in upper before writing, using a 64 KB buffer loop for large files
- `unionfs_create` clears any stale whiteout marker before creating a new file, matching the behaviour of `unionfs_mkdir`
- Whiteout markers follow the `.wh.<filename>` convention used by Docker's overlay driver

## License

MIT — see [LICENSE](LICENSE).
