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

All three directories must already exist. The binary runs in the foreground (`-f` flag) so you can see debug output. Example:

```bash
mkdir -p /tmp/lower /tmp/upper /tmp/mount

# Populate the base image layer
echo "base config" > /tmp/lower/config.txt
echo "base data"   > /tmp/lower/data.txt

# Mount the union filesystem
./mini_unionfs /tmp/lower /tmp/upper /tmp/mount

# In another terminal:
cat /tmp/mount/config.txt      # reads from lower
echo "modified" > /tmp/mount/config.txt  # CoW: copies to upper, writes there
rm /tmp/mount/data.txt         # creates /tmp/upper/.wh.data.txt
```

To unmount:

```bash
fusermount3 -u /tmp/mount
```

## Testing

```bash
bash test_unionfs.sh
```

The test suite validates three scenarios:
1. **Layer visibility** — files in lower_dir appear through the mount
2. **Copy-on-Write** — writing to a lower file copies it to upper; lower stays unchanged
3. **Whiteout deletion** — deleting a lower file creates `.wh.<name>` in upper; file disappears from mount

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
├── test_unionfs.sh    # Automated test suite
└── design_doc.md      # Design document (architecture & edge cases)
```

The codebase is split so each source file can be developed independently and merged without conflicts.

## Architecture

The FUSE operations dispatch table (`struct fuse_operations`) lives in `del_ops.c` and wires every callback to its implementation across the three operation files. Global state (paths to lower_dir and upper_dir) is stored in a `mini_unionfs_state` struct passed through `fuse_get_context()->private_data`.

Key design decisions:
- `readdir` does a two-pass merge (upper first, then lower) with a seen-set to deduplicate entries and suppress whiteout targets
- Open-mode detection uses `(fi->flags & O_ACCMODE) != O_RDONLY` to correctly catch both `O_WRONLY` and `O_RDWR` (since `O_RDONLY == 0`, a naive bitwise AND fails)
- CoW copies preserve the full directory tree in upper before writing
- Whiteout markers follow the `.wh.<filename>` convention used by Docker's overlay driver

## License

MIT — see [LICENSE](LICENSE).
