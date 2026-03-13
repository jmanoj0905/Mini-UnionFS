# CLAUDE.md — Mini-UnionFS

This file gives Claude the context needed to work on this codebase effectively.

---

## Project Overview

**Mini-UnionFS** is a userspace union filesystem built with FUSE (Filesystem in Userspace).
It replicates the core mechanism Docker uses to layer container images: a read-only lower layer stacked under a read-write upper layer, presented as a single unified mount point.

---

## How It Works

### Layer Model

```
mount_dir/          ← unified view (what the user sees)
  ├── file_a.txt    ← from upper_dir (takes precedence)
  └── file_b.txt    ← from lower_dir (read-only base)

upper_dir/          ← read-write container layer
lower_dir/          ← read-only base image layer
```

The binary is invoked as:
```bash
./mini_unionfs <lower_dir> <upper_dir> <mount_dir>
```

---

## Core Mechanics

### 1. Path Resolution (`resolve_path`)
Every FUSE callback must resolve a virtual path to a real path using this priority order:

1. If `upper_dir/.wh.<filename>` exists → file is deleted, return `ENOENT`
2. If `upper_dir/<path>` exists → return upper path
3. If `lower_dir/<path>` exists → return lower path
4. Otherwise → return `ENOENT`

### 2. Copy-on-Write (CoW)
When a user writes to a file that only exists in `lower_dir`:
- Copy the file from `lower_dir` to `upper_dir` (preserving directory structure)
- Apply the write to the `upper_dir` copy
- Leave `lower_dir` untouched

Triggered in: `unionfs_open()` when `O_WRONLY` or `O_RDWR` flags are set.

### 3. Whiteout Files (Deletion)
Deleting a file that originates in `lower_dir` cannot physically remove it.
Instead, create a hidden marker in `upper_dir`:

```
rm mount_dir/config.txt
→ creates upper_dir/.wh.config.txt
```

`resolve_path` checks for this marker and returns `ENOENT`, hiding the file from the user.
Deleting a file that exists only in `upper_dir` is a normal physical `unlink`.

---

## FUSE Operations to Implement

| Operation       | Key Logic |
|----------------|-----------|
| `getattr`      | Resolve path → call `lstat()` on result |
| `readdir`      | Merge entries from both dirs, suppress whiteout targets |
| `read`         | Resolve path → `open()` + `pread()` |
| `write`        | Trigger CoW if needed → write to upper |
| `create`       | Always create in `upper_dir` |
| `unlink`       | Upper-only → physical unlink; lower → create `.wh.<name>` |
| `mkdir`        | Always create in `upper_dir` |
| `rmdir`        | Remove from `upper_dir` |

---

## Global State

```c
struct mini_unionfs_state {
    char *lower_dir;
    char *upper_dir;
};
#define UNIONFS_DATA ((struct mini_unionfs_state *) fuse_get_context()->private_data)
```

Access `lower_dir` and `upper_dir` in any FUSE callback via `UNIONFS_DATA`.

---

## Build & Test

```bash
# Build
make

# Run tests
bash test_unionfs.sh
```

The test suite (`test_unionfs.sh`) validates three scenarios automatically:
- **Test 1 — Layer Visibility**: files in `lower_dir` appear in the mount
- **Test 2 — Copy-on-Write**: writing to a lower file copies it to upper, lower stays clean
- **Test 3 — Whiteout**: deleting a lower file creates `.wh.<name>` in upper, file disappears from mount

---

## Implementation Language

C is the reference language (starter blueprint is in C). C++, Go, or Rust are also acceptable.
Target environment: Ubuntu 22.04 LTS with `libfuse` or `libfuse3`.

---

## Edge Cases to Handle

- **Directory merging**: `readdir` must union-merge both layers and filter out whiteout targets
- **Nested paths**: CoW must recreate the full directory tree in `upper_dir` before copying
- **Double deletion**: unlinking a file that has already been whited out should be a no-op or `ENOENT`
- **Upper-only files**: no CoW needed, operate directly
- **Whiteout of directories**: use `.wh.<dirname>` or implement opaque directory markers

---

## Deliverables

1. Source code (C/C++/Go/Rust)
2. `Makefile` or build script
3. `test_unionfs.sh` — automated test suite
4. 2–3 page Design Document covering data structures and edge case handling

---

## License

MIT — see `LICENSE`.
